# frozen_string_literal: true

require 'logger'
require 'the_help/errors'

module TheHelp
  class Service
    CB_NOT_AUTHORIZED = ->(service:, context:) {
      raise NotAuthorizedError,
            "Not authorized to access #{service.name} as #{context.inspect}."
    }

    class << self
      def call(*args)
        new(*args).call
      end

      def main(&block)
        define_method(:main, &block)
        private :main
      end

      def authorization_policy(allow_all: false, &block)
        if allow_all
          define_method(:authorized?) { true }
        else
          define_method(:authorized?, &block)
        end
        private :authorized?
      end

      def input(name, **options)
        attr_accessor name
        if options.key?(:default)
          required_inputs.delete(name)
          define_method(name) do
            instance_variable_get("@#{name}") || options[:default]
          end
        else
          required_inputs << name
        end
        private name, "#{name}="
      end

      def required_inputs
        @required_inputs ||= Set.new
      end

      def inherited(other)
        other.instance_variable_set(:@required_inputs, required_inputs.dup)
      end
    end

    def initialize(context:, logger: Logger.new($stdout),
                   not_authorized: CB_NOT_AUTHORIZED, **inputs)
      self.class.required_inputs.each do |r_input_name|
        next if inputs.key?(r_input_name)
        raise ArgumentError, "Missing required input: #{r_input_name}."
      end
      inputs.each do |name, value|
        send("#{name}=", value)
      end
      self.context = context
      self.logger = logger
      self.not_authorized = not_authorized
    end

    def call
      raise AbstractClassError if self.class == TheHelp::Service
      raise ServiceNotImplementedError unless defined?(main)
      catch(:stop) do
        authorize!
        logger.info("Service call to #{self.class.name} for #{context.inspect}")
        main
      end
      self
    end

    private

    attr_accessor :context, :logger, :not_authorized

    def authorized?
      false
    end

    def authorize!
      return if authorized?
      logger.warn("Unauthorized attempt to access #{self.class.name} " \
                  "as #{context.inspect}")
      not_authorized.call(service: self.class, context: context)
      throw :stop
    end
  end
end
