require_relative "resourcer/version"
require_relative "resourcer/application_record_extensions"
require_relative "resourcer/list_resourcer"
require_relative "resourcer/object_resourcer"

ActiveSupport.on_load(:active_record) do
  include Resourcer::ApplicationRecordExtensions
end