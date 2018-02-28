# frozen_string_literal: true

module TheHelp
  autoload(:Version, 'the_help/version')
  autoload(:Errors, 'the_help/errors')
  autoload(:ProvidesCallbacks, 'the_help/provides_callbacks')
  autoload(:Service, 'the_help/service')
  autoload(:ServiceCaller, 'the_help/service_caller')

  include Errors
end
