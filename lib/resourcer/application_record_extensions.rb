module Resourcer::ApplicationRecordExtensions
  extend ActiveSupport::Concern

  attr_accessor :resourcer

  # Provides a resourcer method for all ActiveRecord objects to access an ObjectResourcer.
  # Returns the specific resourcer assigned to the object or a default resourcer if none is assigned.
  def resourcer
    @resourcer || default_resourcer
  end

  # Returns a default ObjectResourcer if no specific ObjectResourcer is applied to the object.
  # This ensures that calls to methods like object.resourcer.some_method will not raise an error,
  # provided that some_method is defined on the ActiveRecord object.
  def default_resourcer
    @default_resourcer ||= Resourcer::ObjectResourcer.new(self, nil)
  end

  # Returns the resourcer for the wrapped object, or creates one from itself
  def auto_resourcer
    @auto_resourcer ||= is_resourced? ? resourcer : resourcer_klass.build(self).first.resourcer
  end

  # Applies a ListResourcer to the object, creating an ObjectResourcer and assigning it to the object's "resourcer" property.
  # Returns self to allow for method chaining.
  def apply_resourcer(list_resourcer)
    self.resourcer = list_resourcer.build_object_resourcer(self)
    self
  end

  # Checks if the object has a specific resourcer assigned. The default resourcer is not considered.
  def is_resourced?
    @resourcer.present?
  end

  # Delegates method calls to the resourcer if it responds to the method.
  # This allows the resourcer to act as a proxy for methods defined on the resourcer.
  def method_missing(m, ...)
    if resourcer.try(:respond_to?, m)
      resourcer.send(m, ...)
    else
      super
    end
  end

  # Utility method for accessing the specific subclass of ListResourcer that is managing the object.
  # Available as both a class and instance method.
  def resourcer_klass
    self.class.resourcer_klass
  end

  class_methods do
    # Returns the class name of the resourcer for the model.
    def resourcer_class_name
      name + "Resourcer"
    end

    # Returns the constantized class of the resourcer for the model.
    def resourcer_klass
      resourcer_class_name.constantize
    end
  end
end
