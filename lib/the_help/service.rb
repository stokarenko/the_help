require 'the_help/errors'

module TheHelp
  class Service
    ALLOW = true

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

      def input(name, **options)
        required_inputs << name unless options.key?(:default)
        attr_writer name
        define_method(name) do
          instance_variable_get("@#{name}") || options[:default]
        end
        private name, "#{name}="
      end

      def required_inputs
        @required_inputs ||= Set.new
      end
    end

    def initialize(context:, not_authorized: CB_NOT_AUTHORIZED, **inputs)
      self.class.required_inputs.each do |r_input_name|
        next if inputs.key?(r_input_name)
        raise ArgumentError, "Missing required input: #{r_input_name}."
      end
      inputs.each do |name, value|
        send("#{name}=", value)
      end
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
