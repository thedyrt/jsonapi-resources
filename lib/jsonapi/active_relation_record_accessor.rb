require 'jsonapi/record_accessor'

module JSONAPI
  class ActiveRelationRecordAccessor < RecordAccessor

    # RecordAccessor methods

    def find(filters, options = {})
      if defined?(_resource_klass.find_records)
        ActiveSupport::Deprecation.warn "In #{_resource_klass.name} you overrode `find_records`. "\
                                        "`find_records` has been deprecated in favor of using `apply` "\
                                        "and `verify` callables on the filter."

        _resource_klass.find_records(filters, options)
      else
        context = options[:context]

        records = filter_records(filters, options)

        sort_criteria = options.fetch(:sort_criteria) { [] }
        order_options = _resource_klass.construct_order_options(sort_criteria)
        records = sort_records(records, order_options, context)

        records = apply_pagination(records, options[:paginator], order_options)

        records
      end
    end

    def count(filters, options = {})
      count_records(filter_records(filters, options))
    end

    def find_by_key(key, options = {})
      records = find({ _resource_klass._primary_key => key }, options.except(:paginator, :sort_criteria))
      record = records.first
      fail JSONAPI::Exceptions::RecordNotFound.new(key) if record.nil?
      record
    end

    def find_by_keys(keys, options = {})
      records = records(options)
      records = apply_includes(records, options)
      records.where({ _resource_klass._primary_key => keys })
    end

    def find_by_relationship(resource, relationship_name, options = {})
      relationship = resource.class._relationships[relationship_name.to_sym]

      context = resource.context

      relation_name = relationship.relation_name(context: context)
      records = records_for(resource, relation_name)

      resource_klass = relationship.resource_klass

      filters = options.fetch(:filters, {})
      unless filters.nil? || filters.empty?
        records = resource_klass._record_accessor.apply_filters(records, filters, options)
      end

      sort_criteria = options.fetch(:sort_criteria, {})
      order_options = relationship.resource_klass.construct_order_options(sort_criteria)
      records = apply_sort(records, order_options, context)

      paginator = options[:paginator]
      if paginator
        records = apply_pagination(records, paginator, order_options)
      end

      records
    end

    def count_for_relationship(resource, relationship_name, options = {})
      relationship = resource.class._relationships[relationship_name.to_sym]

      context = resource.context

      relation_name = relationship.relation_name(context: context)
      records = records_for(resource, relation_name)

      resource_klass = relationship.resource_klass

      filters = options.fetch(:filters, {})
      unless filters.nil? || filters.empty?
        records = resource_klass._record_accessor.apply_filters(records, filters, options)
      end

      records.count(:all)
    end

    # protected-ish methods left public for tests and what not

    # Implement self.records on the resource if you want to customize the relation for
    # finder methods (find, find_by_key, find_serialized_with_caching)
    def records(_options = {})
      if defined?(_resource_klass.records)
        _resource_klass.records(_options)
      else
        _resource_klass._model_class.all
      end
    end

    # Implement records_for on the resource to customize how the associated records
    # are fetched for a model. Particularly helpful for authorization.
    def records_for(resource, relation_name)
      if resource.respond_to?(:records_for)
        return resource.records_for(relation_name)
      end

      relationship = resource.class._relationships[relation_name]

      if relationship.is_a?(JSONAPI::Relationship::ToMany)
        if resource.respond_to?(:"records_for_#{relation_name}")
          return resource.method(:"records_for_#{relation_name}").call
        end
      else
        if resource.respond_to?(:"record_for_#{relation_name}")
          return resource.method(:"record_for_#{relation_name}").call
        end
      end

      resource._model.public_send(relation_name)
    end

    def apply_includes(records, options = {})
      include_directives = options[:include_directives]
      if include_directives
        model_includes = resolve_relationship_names_to_relations(_resource_klass, include_directives.model_includes, options)
        records = records.includes(model_includes)
      end

      records
    end

    def apply_pagination(records, paginator, order_options)
      records = paginator.apply(records, order_options) if paginator
      records
    end

    def apply_sort(records, order_options, context = {})
      if defined?(_resource_klass.apply_sort)
        _resource_klass.apply_sort(records, order_options, context)
      else
        if order_options.any?
          order_options.each_pair do |field, direction|
            if field.to_s.include?(".")
              *model_names, column_name = field.split(".")

              associations = _lookup_association_chain([records.model.to_s, *model_names])
              joins_query = _build_joins([records.model, *associations])

              # _sorting is appended to avoid name clashes with manual joins eg. overridden filters
              order_by_query = "#{associations.last.name}_sorting.#{column_name} #{direction}"
              records = records.joins(joins_query).order(order_by_query)
            else
              records = records.order(field => direction)
            end
          end
        end

        records
      end
    end

    def _lookup_association_chain(model_names)
      associations = []
      model_names.inject do |prev, current|
        association = prev.classify.constantize.reflect_on_all_associations.detect do |assoc|
          assoc.name.to_s.downcase == current.downcase
        end
        associations << association
        association.class_name
      end

      associations
    end

    def _build_joins(associations)
      joins = []

      associations.inject do |prev, current|
        joins << "LEFT JOIN #{current.table_name} AS #{current.name}_sorting ON #{current.name}_sorting.id = #{prev.table_name}.#{current.foreign_key}"
        current
      end
      joins.join("\n")
    end

    def apply_filter(records, filter, value, options = {})
      strategy = _resource_klass._allowed_filters.fetch(filter.to_sym, Hash.new)[:apply]

      if strategy
        if strategy.is_a?(Symbol) || strategy.is_a?(String)
          _resource_klass.send(strategy, records, value, options)
        else
          strategy.call(records, value, options)
        end
      else
        records.where(filter => value)
      end
    end

    # Assumes ActiveRecord's counting. Override if you need a different counting method
    def count_records(records)
      records.count(:all)
    end

    def resolve_relationship_names_to_relations(resource_klass, model_includes, options = {})
      case model_includes
        when Array
          return model_includes.map do |value|
            resolve_relationship_names_to_relations(resource_klass, value, options)
          end
        when Hash
          model_includes.keys.each do |key|
            relationship = resource_klass._relationships[key]
            value = model_includes[key]
            model_includes.delete(key)
            model_includes[relationship.relation_name(options)] = resolve_relationship_names_to_relations(relationship.resource_klass, value, options)
          end
          return model_includes
        when Symbol
          relationship = resource_klass._relationships[model_includes]
          return relationship.relation_name(options)
      end
    end

    def apply_filters(records, filters, options = {})
      required_includes = []

      if filters
        filters.each do |filter, value|
          if _resource_klass._relationships.include?(filter)
            if _resource_klass._relationships[filter].belongs_to?
              records = apply_filter(records, _resource_klass._relationships[filter].foreign_key, value, options)
            else
              required_includes.push(filter.to_s)
              records = apply_filter(records, "#{_resource_klass._relationships[filter].table_name}.#{_resource_klass._relationships[filter].primary_key}", value, options)
            end
          else
            records = apply_filter(records, filter, value, options)
          end
        end
      end

      if required_includes.any?
        records = apply_includes(records, options.merge(include_directives: IncludeDirectives.new(_resource_klass, required_includes, force_eager_load: true)))
      end

      records
    end

    def filter_records(filters, options, records = records(options))
      records = apply_filters(records, filters, options)
      apply_includes(records, options)
    end

    def sort_records(records, order_options, context = {})
      apply_sort(records, order_options, context)
    end
  end
end
