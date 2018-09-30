# frozen_string_literal: true

module TheHelp
  # Provides convenience method for calling services
  #
  # The including module/class MUST provide the #service_context and
  # #service_logger methods, which will be provided as the called-service's
  # `context` and `logger` arguments, respectively.
  #
  # @example
  #   class Foo
  #     include TheHelp::ServiceCaller
  #
  #     def do_something
  #       call_service(MyService, some: 'arguments')
  #     end
  #
  #     private
  #
  #     def service_context
  #       # something that provides the context
  #     end
  #
  #     def service_logger
  #       # an instance of a `Logger`
  #     end
  #   end
  module ServiceCaller
    # Calls the specified service
    #
    # @param service [Class<TheHelp::Service>]
    # @param args [Hash<Symbol, Object>] Any additional keyword arguments are
    #        passed directly to the service.
    # @return [self]
    def call_service(service, **args, &block)
      service_args = {
        context: service_context,
        logger: service_logger
      }.merge(args)
      service_logger.debug("#{self.class.name}/#{__id__} called service " \
                           "#{service.name}")
      service.call(**service_args, &block)
    end
  end
end
