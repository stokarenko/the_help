require 'the_help/errors'

module TheHelp
  class Service
    CB_NOT_AUTHORIZED = ->(service:, context:) {
      raise NotAuthorizedError, "Not authorized to access #{service.name} as #{context.inspect}."
    }

    class << self
      def call(*args)
        new(*args).call
      end

      def main(&block)
        define_method(:main, &block)
        private :main
      end

      def authorization_policy(&block)
        define_method(:authorized?, &block)
        private :authorized?
      end
    end

    def initialize(context:, not_authorized: CB_NOT_AUTHORIZED)
      self.context = context
      self.not_authorized = not_authorized
    end

    def call
      raise AbstractClassError if self.class == TheHelp::Service
      raise ServiceNotImplementedError unless defined?(main)
      catch(:stop) do
        authorize!
        main
      end
      self
    end

    private

    attr_accessor :context, :not_authorized

    def authorized?
      false
    end

    def authorize!
      return if authorized?
      not_authorized.call(service: self.class, context: context)
      throw :stop
    end
  end
end
