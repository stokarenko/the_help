# frozen_string_literal: true

require 'logger'
require 'set'
require 'the_help/errors'
require 'the_help/provides_callbacks'
require 'the_help/service_caller'

module TheHelp
  # An Abstract Service Class with Authorization and Logging
  #
  # Define subclasses of Service to build out the service layer of your
  # application.
  #
  # @example
  # class CreateNewUserAccount < TheHelp::Service
  #   input :user
  #   input :send_welcome_message, default: true
  #
  #   authorization_policy do
  #     authorized = false
  #     call_service(Authorize, permission: :admin_users,
  #                  allowed: ->() { authorized = true })
  #     authorized
  #   end
  #
  #   main do
  #     # do something to create the user account
  #     if send_welcome_message
  #       call_service(SendWelcomeMessage, user: user,
  #                    success: callback(:message_sent))
  #     end
  #   end
  #
  #   callback(:message_sent) do
  #     # do something really important, I'm sure
  #   end
  # end
  #
  # class Authorize < TheHelp::Service
  #   input :permission
  #   input :allowed
  #
  #   authorization_policy allow_all: true
  #
  #   main do
  #     if user_has_permission?
  #       allowed.call
  #     end
  #   end
  # end
  #
  # class SendWelcomeMessage < TheHelp::Service
  #   input :user
  #   input :success, default: ->() { }
  #
  #   main do
  #     # whatever
  #     success.call
  #   end
  # end
  #
  # CreateNewUserAccount.(context: current_user, user: new_user_object)
  class Service
    include ProvidesCallbacks
    include ServiceCaller

    # The default :not_authorized callback
    #
    # It will raise a TheHelp::NotAuthorizedError when the context is not
    # authorized to perform the service.
    CB_NOT_AUTHORIZED = ->(service:, context:) {
      raise NotAuthorizedError,
            "Not authorized to access #{service.name} as #{context.inspect}."
    }

    class << self
      # Defines attr_accessors with scoping options
      def attr_accessor(*names, make_private: false, private_reader: false,
                        private_writer: false)
        super(*names)
        names.each do |name|
          private name if make_private || private_reader
          private "#{name}=" if make_private || private_writer
        end
      end

      # Convenience method to instantiate the service and immediately call it
      #
      # Any arguments are passed to #initialize
      #
      # @return [Class] Returns the receiver
      def call(*args)
        new(*args).call
        self
      end

      # :nodoc:
      def inherited(other)
        other.instance_variable_set(:@required_inputs, required_inputs.dup)
      end

      # :nodoc:
      # instances need access to this, otherwise it would be made private
      def required_inputs
        @required_inputs ||= Set.new
      end

      # Defines the primary routine of the service
      #
      # The code that will be run when the service is called, assuming it is
      # unauthorized.
      def main(&block)
        define_method(:main, &block)
        private :main
        self
      end

      # Defines the service authorization policy
      #
      # If allow_all is set to true, or if the provided block (executed in the
      # context of the service object) returns true, then the service will be
      # run when called. Otherwise, the not_authorized callback will be invoked.
      #
      # @param allow_all [Boolean]
      # @param block [Proc] executed in the context of the service instance (and
      #   can therefore access all inputs to the service)
      def authorization_policy(allow_all: false, &block)
        if allow_all
          define_method(:authorized?) { true }
        else
          define_method(:authorized?, &block)
        end
        private :authorized?
        self
      end

      def input(name, **options)
        attr_accessor name, make_private: true
        if options.key?(:default)
          required_inputs.delete(name)
          define_method(name) do
            instance_variable_get("@#{name}") || options[:default]
          end
        else
          required_inputs << name
        end
        self
      end
    end

    def initialize(context:, logger: Logger.new($stdout),
                   not_authorized: CB_NOT_AUTHORIZED, **inputs)
      self.context = context
      self.logger = logger
      self.not_authorized = not_authorized
      self.inputs = inputs
    end

    def call
      validate_service_definition
      catch(:stop) do
        authorize
        log_service_call
        main
      end
      self
    end

    private

    attr_accessor :context, :logger, :not_authorized
    attr_reader :inputs

    alias service_context context
    alias service_logger logger

    def inputs=(inputs)
      @inputs = inputs
      inputs.each { |name, value| send("#{name}=", value) }
      validate_inputs
    end

    def validate_inputs
      self.class.required_inputs.each do |r_input_name|
        next if inputs.key?(r_input_name)
        raise ArgumentError, "Missing required input: #{r_input_name}."
      end
    end

    def validate_service_definition
      raise AbstractClassError if self.class == TheHelp::Service
      raise ServiceNotImplementedError unless defined?(main)
    end

    def log_service_call
      logger.info("Service call to #{self.class.name} for #{context.inspect}")
    end

    def authorized?
      false
    end

    def authorize
      return if authorized?
      logger.warn("Unauthorized attempt to access #{self.class.name} " \
                  "as #{context.inspect}")
      not_authorized.call(service: self.class, context: context)
      throw :stop
    end

    def stop!
      throw :stop
    end
  end
end
