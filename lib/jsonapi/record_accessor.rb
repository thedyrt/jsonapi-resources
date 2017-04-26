module JSONAPI
  class RecordAccessor
    attr_reader :_resource_klass

    def initialize(resource_klass)
      @_resource_klass = resource_klass
    end

    # Finds model records by applying filters, sorting, and pagination
    # Returns an array of model records, or an object that acts as one such as an ActiveRecord::Relation
    def find(_filters, _options = {})
      # :nocov:
      raise 'Abstract method called'
      # :nocov:
    end

    # Returns a counts of model records after apply filters
    def count(_filters, _options = {})
      # :nocov:
      raise 'Abstract method called'
      # :nocov:
    end

    # Finds a model record by key
    # Returns a model record
    def find_by_key(_key, _options = {})
      # :nocov:
      raise 'Abstract method called'
      # :nocov:
    end

    # Finds model records by an array of keys
    # Returns an array of model records, or an object that acts as one such as an ActiveRecord::Relation
    def find_by_keys(_keys, _options = {})
      # :nocov:
      raise 'Abstract method called'
      # :nocov:
    end

    # Finds model records from a relationship on a resource instance
    # Returns an array of model records, or an object that acts as one such as an ActiveRecord::Relation
    def find_by_relationship(_resource, _relationship_name, _options = {})
      # :nocov:
      raise 'Abstract method called'
      # :nocov:
    end

    # Returns a counts of model records from a relationship on a resource instance
    def count_for_relationship(_resource, _relationship_name, _options = {})
      # :nocov:
      raise 'Abstract method called'
      # :nocov:
    end
  end
end