# The Resourcer::ListResourcer class is a foundational component designed to enhance data retrieval and management
# efficiency within a Ruby on Rails application. It addresses common ORM issues like the N+1 query problem
# by pre-fetching and indexing necessary data, thus enabling quick and efficient access to related data
# without the need for additional database queries.

# Key Features:
# 1. Data Pre-fetching: Automatically gathers and organizes data upon initialization, significantly reducing
#    the need for repeated database hits.
# 2. Deferred Execution: Implements lazy loading where data processing and queries are executed only upon
#    demand, optimizing performance and resource utilization.
# 3. Modular Design: Facilitates easy extension to manage different types of resources, enhancing reuse and
#    maintainability throughout the application.

# For an example of implementation, please refer to CompanyResourcer

class Resourcer::ListResourcer
  class_attribute :indexed_fields
  self.indexed_fields = []

  attr_accessor :unkeyed_list
  attr_accessor :object_id_list
  attr_accessor :object_lookup
  attr_accessor :unique_values
  attr_accessor :grouped_object_lookup

  def initialize(list)
    assimilate(list)
  end

  # Assimilates a given list of objects into the resourcer. The list can be a relation, an array of objects, or a single object.
  # - Indexes each object by its primary key.
  # - Stores unique values for each indexed field defined by index_by method in the subclass.
  # - Groups objects by their indexed field values.
  # - If an object is not already resourced, it applies the ObjectResourcer to it.
  # - Marks all objects as pre-fetched using Fetchable.register_object for potential later use.
  # - Updates the ListResourcer if new objects are added to an already assimilated list.
  def assimilate(list)
    list = list.is_a?(ActiveRecord::Relation) ? list.dup.to_a : [list].flatten.compact

    self.unique_values = self.class.indexed_fields.each_with_object({}) { |field, hash| hash[field] = [] }
    self.grouped_object_lookup = self.class.indexed_fields.each_with_object({}) { |field, hash| hash[field] = {} }

    list.each do |obj|
      if pk.nil? || !object_id_list.include?(obj.send(pk))
        obj.apply_resourcer(self) unless obj.is_resourced?
        if pk.present?
          ::Fetchable.register_object(obj)
          object_id_list << obj.send(pk)
          object_lookup[obj.send(pk)] = obj
        end

        # Add any unique values to the unique_values hash
        self.class.indexed_fields.each do |fieldname|
          FIELD_INDEXER.call(obj, fieldname, unique_values, grouped_object_lookup)
        end
      end
    end

    if pk.nil?
      self.unkeyed_list = (unkeyed_list + list).uniq
    end

    unique_values.each { |k, v| unique_values[k] = v.uniq }
    grouped_object_lookup.each { |k, v| v.each { |k2, v2| v[k2] = v2.uniq } }
  end

  # Lambda function to index unique field values and group objects by these values.
  FIELD_INDEXER = lambda do |obj, fieldname, unique_values, grouped_object_lookup|
    unique_values[fieldname.to_sym] ||= []
    unique_values[fieldname.to_sym] << obj.send(fieldname)
    grouped_object_lookup[fieldname.to_sym] ||= {}
    grouped_object_lookup[fieldname.to_sym][obj.send(fieldname)] ||= []
    grouped_object_lookup[fieldname.to_sym][obj.send(fieldname)] << obj
  end

  # Called when a subclass is inherited. Dynamically adds methods to handle indexed fields and object lookups.
  def self.inherited(subclass)
    subclass.indexed_fields = []

    unless subclass.const_defined?(:ObjectResourcerMethods, false)
      subclass.const_set(:ObjectResourcerMethods, Module.new)
    end

    subclass.alias_method "#{subclass.managed_klass.name.underscore}_id_list".to_sym, :object_id_list
    subclass.alias_method "#{subclass.managed_klass.name.underscore}_lookup".to_sym, :object_lookup
    subclass.alias_method "#{subclass.managed_klass.name.underscore}_list".to_sym, :object_list
  end

  # Defines fields to be indexed. Unique values and grouped objects can be accessed by these fields.
  # Adds dynamic methods for retrieving unique values, grouped objects, and lists of objects by indexed fields.
  def self.index_by(*fieldnames)
    fieldnames.each do |fieldname|
      indexed_fields << fieldname.to_sym

      define_method("unique_#{fieldname}_list") do
        unique_values_for(fieldname)
      end

      define_method("grouped_by_#{fieldname}") do
        grouped_object_lookup_for(fieldname)
      end

      define_method("list_for_#{fieldname}") do |key|
        key.is_a?(Array) \
          ? key.flat_map { |k| send("grouped_by_#{fieldname}")[k] }.compact.uniq || []
          : send("grouped_by_#{fieldname}")[key] || []
      end
    end
  end

  # Defines relationships to other models. Generates methods for belongs_to and has_many associations.
  def self.relates_to(*associations)
    options = associations.extract_options!
    associations.each do |association|
      define_resourcer_methods(association, options)
    end
  end

  # Defines methods to handle belongs_to and has_many associations for the given relationship.
  def self.define_resourcer_methods(association, options = {})
    reflection = managed_klass.reflect_on_association(association) unless options[:manual]
    class_name = options[:class_name] || reflection&.class_name || association.to_s.classify
    foreign_key = options[:foreign_key] || reflection&.foreign_key || "#{association}_id"
    association_type = options[:type] || reflection&.macro
    association_singularized = association.to_s.singularize

    case association_type
    when :belongs_to
      define_belongs_to_resourcer(association, foreign_key, class_name, options)
    when :has_many
      define_has_many_resourcer(association, foreign_key, class_name, options)
    else
      raise "Unsupported association type: #{association_type}"
    end

    define_method("#{association_singularized}_id_list") { send("#{association_singularized}_resourcer").object_id_list }
    define_method("#{association_singularized}_list") { send("#{association_singularized}_resourcer").object_list }
    define_method("#{association_singularized}_lookup") { send("#{association_singularized}_resourcer").lookup }
  end

  # Defines methods to handle belongs_to associations. Creates resourcers for the associated class.
  def self.define_belongs_to_resourcer(association, foreign_key, class_name, options = {})
    managed_klass = class_name.constantize
    resourcer_klass = managed_klass.resourcer_klass
    association_singularized = association.to_s.singularize

    index_by foreign_key

    define_method("#{association_singularized}_resourcer") do
      instance_variable_get("@#{association_singularized}_resourcer") || instance_variable_set(
        "@#{association_singularized}_resourcer",
        resourcer_klass.new(managed_klass.in_list(managed_klass.primary_key, unique_values_for(foreign_key)))
      )
    end

    const_get(:ObjectResourcerMethods).module_eval do
      define_method(association) do
        instance_variable_get("@#{association}") || instance_variable_set(
          "@#{association}",
          send("#{association_singularized}_resourcer").lookup(object.send(foreign_key))
        )
      end
    end
  end

  # Defines methods to handle has_many associations. Creates resourcers for the associated class.
  def self.define_has_many_resourcer(association, foreign_key, class_name, options = {})
    managed_klass = class_name.constantize
    resourcer_klass = managed_klass.resourcer_klass
    association_singularized = association.to_s.singularize

    define_method("#{association_singularized}_resourcer") do
      instance_variable_get("@#{association_singularized}_resourcer") || instance_variable_set(
        "@#{association_singularized}_resourcer",
        resourcer_klass.new(managed_klass.in_list(foreign_key, id_list))
      )
    end

    const_get(:ObjectResourcerMethods).module_eval do
      define_method(association) do
        instance_variable_get("@#{association}") || instance_variable_set(
          "@#{association}",
          send("#{association_singularized}_resourcer").send("list_for_#{foreign_key}", primary_key)
        )
      end
    end
  end

  # used only when there is no primary key
  def unkeyed_list
    @unkeyed_list ||= []
  end

  # Returns the list of all ids of the objects assimilated by the resourcer.
  def object_id_list
    @object_id_list ||= []
  end
  alias_method :id_list, :object_id_list

  # Returns a hash of all objects assimilated by the resourcer, indexed by their primary key
  def object_lookup
    @object_lookup ||= {}
  end

  # Returns the object with the given primary key. If the key is an array, returns an array of matching objects
  def lookup(key)
    key.is_a?(Array) \
      ? key.map { |k| object_lookup[k] }.compact.uniq
      : object_lookup[key]
  end

  # Returns the list of all objects assimilated by the resourcer as an array
  def object_list
    @object_list ||= (pk.present? ? object_lookup.values : unkeyed_list) || []
  end
  alias_method :list, :object_list

  # Creates an index for a field unless it already exists.
  # This ensures unique values and grouped object lookups are up-to-date.
  def create_index_unless_exists_for(fieldname)
    if !unique_values.has_key?(fieldname.to_sym)
      object_list.each do |obj|
        FIELD_INDEXER.call(obj, fieldname, unique_values, grouped_object_lookup)
      end
      unique_values.each { |k, v| unique_values[k] = v.uniq }
      grouped_object_lookup.each { |k, v| v.each { |k2, v2| v[k2] = v2.uniq } }
    end
  end

  # Returns a hash of all unique values for every indexed field.
  def unique_values
    @unique_values ||= {}
  end

  # Returns the list of unique values for the given field.
  def unique_values_for(fieldname)
    create_index_unless_exists_for(fieldname)
    unique_values[fieldname.to_sym] || []
  end

  # Returns a hash of all objects assimilated by the resourcer, grouped by the given field.
  def grouped_object_lookup
    @grouped_object_lookup ||= {}
  end

  # Returns the list of objects with the given value for the given field.
  def grouped_object_lookup_for(fieldname)
    create_index_unless_exists_for(fieldname)
    grouped_object_lookup[fieldname.to_sym] || {}
  end

  # Applies the resourcer (self) to the "resourcer" property of the given object.
  def apply_to(obj)
    obj.apply_resourcer(self)
  end

  # Builds an ObjectResourcer for the given object, extending it with the ObjectResourcerMethods module
  # defined in the appropriate subclass of ListResourcer.
  def build_object_resourcer(obj)
    object_resourcer = Resourcer::ObjectResourcer.new(obj, self)
    object_resourcer.extend(self.class::ObjectResourcerMethods)
    object_resourcer
  end

  # Receives a list of objects, either as an array or an ActiveRecord::Relation, and returns a new
  # ListResourcer object of the appropriate subclass, assimilating the objects in the process.
  def self.build(object_list)
    object_list = object_list.to_a if object_list.is_a?(ActiveRecord::Relation)
    resourcer = new(object_list)
    resourcer.object_list
  end

  # Returns the class that is being managed by the resourcer class.
  def self.managed_klass
    name.gsub(/Resourcer$/, "").constantize
  end

  def managed_klass
    self.class.managed_klass
  end

  # Returns the primary key of the managed class.
  def self.pk
    managed_klass.primary_key
  end

  def pk
    self.class.pk
  end

  # Default empty module for methods to be implemented in subclasses.
  module ObjectResourcerMethods
  end
end
