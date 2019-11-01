# frozen_string_literal: true

require 'logger'
require 'set'

module TheHelp
  # An Abstract Service Class with Authorization and Logging
  #
  # Define subclasses of Service to build out the service layer of your
  # application.
  #
  # @example
  #   class CreateNewUserAccount < TheHelp::Service
  #     input :user
  #     input :send_welcome_message, default: true
  #
  #     authorization_policy do
  #       call_service(Authorize, permission: :admin_users).success?
  #     end
  #
  #     main do
  #       # do something to create the user account
  #       if send_welcome_message
  #         call_service(SendWelcomeMessage, user: user) do |result|
  #           callback(:message_sent) if result.success?
  #         end
  #       end
  #       result.success
  #     end
  #
  #     callback(:message_sent) do |message|
  #       # do something really important with `message`, I'm sure
  #     end
  #   end
  #
  #   class Authorize < TheHelp::Service
  #     input :permission
  #
  #     authorization_policy allow_all: true
  #
  #     main do
  #       if user_has_permission?
  #         result.success
  #       else
  #         result.error 'Permission Denied'
  #       end
  #     end
  #   end
  #
  #   class SendWelcomeMessage < TheHelp::Service
  #     input :user
  #
  #     main do
  #       message = 'Hello, world!'
  #       # do something with message...
  #       result.success message
  #     end
  #   end
  #
  #   CreateNewUserAccount.(context: current_user, user: new_user_object)
  #
  # @example Calling services with a block
  #
  #   # The service result will be yielded to the block if a block is present.
  #
  #   class CanTakeABlock < TheHelp::Service
  #     authorization_policy allow_all: true
  #
  #     main do
  #       result.success :the_service_result
  #     end
  #   end
  #
  #   service_result = nil
  #
  #   CanTakeABlock.call { |result| service_result = result.value }
  #
  #   service_result
  #   #=> :the_service_result
  #
  # @note See README section "Running Callbacks"
  class Service
    include ProvidesCallbacks
    include ServiceCaller

    # The default :not_authorized callback
    #
    # It will raise a TheHelp::NotAuthorizedError when the context is not
    # authorized to perform the service.
    CB_NOT_AUTHORIZED = ->(service:, context:) {
      raise TheHelp::NotAuthorizedError,
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
      def call(*args, &block)
        new(*args).call(&block)
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

    # Holds the result of running a service as well as the execution status
    #
    # An instance of this class will be returned from any service call and will have a status of
    # either :success or :error along with a value that is set by the service.
    class Result
      attr_reader :status, :value

      def initialize
        self.status = :pending
        self.value = nil
      end

      def pending?
        status == :pending
      end

      def success?
        status == :success
      end

      def error?
        status == :error
      end

      def success(value = nil)
        self.value = value
        self.status = :success
        freeze
      end

      def error(value = nil, &block)
        self.value = if block_given?
                       begin
                        self.value = block.call
                       rescue StandardError => e
                         e
                       end
                     else
                       value
                     end
        self.status = :error
        freeze
      end

      def value!
        raise TheHelp::NoResultError if pending?

        raise value if error? && value.is_a?(Exception)

        raise TheHelp::ResultError.new(value) if error?

        value
      end

      private

      attr_writer :status, :value
    end

    def initialize(context:, logger: Logger.new($stdout),
                   not_authorized: CB_NOT_AUTHORIZED, **inputs)
      @result = Result.new

      self.context = context
      self.logger = logger
      self.not_authorized = not_authorized
      self.inputs = inputs
      self.stop_caller = false
    end

    # Executes the service and returns the result
    #
    # @return [TheHelp::Service::Result]
    def call
      validate_service_definition
      catch(:stop) do
        authorize
        log_service_call
        main
        check_result!
        self.block_result = yield result if block_given?
      end
      throw :stop if stop_caller
      return block_result if block_given?
      return result
    end

    private

    attr_accessor :context, :logger, :not_authorized, :block_result,
                  :stop_caller
    attr_reader :inputs, :result

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
      raise TheHelp::AbstractClassError if self.class == TheHelp::Service
      raise TheHelp::ServiceNotImplementedError unless defined?(main)
    end

    def log_service_call
      logger.debug("Service call to #{self.class.name}/#{__id__} " \
                   "for #{context.inspect}")
    end

    def authorized?
      false
    end

    def authorize
      return if authorized?
      logger.warn("Unauthorized attempt to access #{self.class.name}/#{__id__} " \
                  "as #{context.inspect}")
      run_callback(not_authorized, service: self.class, context: context)
      stop!
    end

    def stop!
      throw :stop
    end

    def check_result!
      raise TheHelp::NoResultError if result.pending?
    end

    def run_callback(callback, *args)
      continue = false
      continue = catch(:stop) do
        callback.call(*args)
        true
      end
      self.stop_caller ||= !continue
    end
  end
end
