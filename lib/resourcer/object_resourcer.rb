# The Resourcer::ObjectResourcer class wraps and pairs an ActiveRecord object with a provided ListResourcer object.
# This allows additional related data to be accessed through the ActiveRecord object via the "resourcer" attribute.

# The ObjectResourcer is extended with the ObjectResourcerMethods module defined in the appropriate
# subclass of ListResourcer. This enables the definition of custom methods for each ObjectResourcer.

class Resourcer::ObjectResourcer
  attr_accessor :object
  attr_accessor :list_resourcer

  # Initializes a new ObjectResourcer.
  # - obj: The ActiveRecord object to be wrapped.
  # - list_resourcer: The ListResourcer object that manages the collection of related objects.
  def initialize(obj, list_resourcer)
    self.object = obj
    self.list_resourcer = list_resourcer

    # The original, unmodified object is made accessible through an alias named after the object's class name.
    define_singleton_method object.class.name.underscore do
      object
    end
  end

  # Returns the primary key of the wrapped object.
  def primary_key
    @primary_key ||= send(object.class.primary_key || :id)
  end

  # Delegates method calls to the list_resourcer if it responds to the method.
  # If not, it delegates to the wrapped object.
  # This allows the ObjectResourcer to act as a proxy for both the list_resourcer and the original object.
  def method_missing(m, ...)
    if list_resourcer&.respond_to?(m)
      list_resourcer.send(m, ...)
    elsif object.respond_to?(m)
      object.send(m, ...)
    else
      super
    end
  end
end
