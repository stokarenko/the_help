# frozen_string_literal: true

module TheHelp
  # Adds a callback DSL to including classes
  #
  # @example
  #   class Foo
  #     attr_accessor :collaborator
  #
  #     def do_something
  #       collaborator.do_some_other_thing(when_done: callback(:it_was_done))
  #       collaborator
  #         .do_some_other_thing(when_done: callback(:it_was_done_method))
  #     end
  #
  #     callback(:it_was_done) do |some_arg:|
  #       puts "Yay! #{some_arg}"
  #     end
  #
  #     def it_was_done_method(some_arg:)
  #       puts "In a method: #{some_arg}"
  #     end
  #     callback :it_was_done_method
  #   end
  #
  #   class Bar
  #    def do_some_other_thing(when_done:)
  #      when_done.call('done by Bar')
  #    end
  #   end
  #
  #   f = Foo.new
  #   f.collaborator = Bar.new
  #   f.do_something
  #   # STDOUT: "Yay! done by Bar"
  #   # STDOUT: "In a method: done by Bar"
  #
  # If the including class defines a #logger instance method, a debug-level
  # message will be logged indicating that the callback was invoked.
  module ProvidesCallbacks
    def self.included(other)
      other.class_eval do
        extend TheHelp::ProvidesCallbacks::ClassMethods
        alias_method :callback, :method
      end
    end

    # Classes that include ProvidesCallbacks are extended with these
    # ClassMethods
    module ClassMethods
      private

      # Defines a callback method on the class
      #
      # Regardless of whether the callback is pointing to an existing instance
      # method or if it is defined via the block argument, the callback will
      # also be wrapped in logging statements that can help you trace the
      # execution path through your code in the event of any anomolies.
      #
      # @param name [Symbol] The name of the callback. If no block is provided,
      #        then name must be the name of an existing instance method.
      # @param block [Proc] If a block is provided, the block will act as the
      #        though it is the body of an instance method when the callback is
      #        invoked.
      # @return [self]
      def callback(name, &block)
        without_logging = "#{name}_without_logging".to_sym
        provides_callbacks_define_method_with_block(without_logging, &block)
        provides_callbacks_alias_method(without_logging, name)
        provides_callbacks_define_wrapper(name, without_logging)
        self
      end

      def provides_callbacks_method_defined?(name)
        method_defined?(name) || private_method_defined?(name)
      end

      def provides_callbacks_define_method_with_block(without_logging, &block)
        return unless block_given?

        define_method(without_logging, &block)
        private without_logging
      end

      def provides_callbacks_alias_method(without_logging, name)
        return unless provides_callbacks_method_defined?(name)

        alias_method without_logging, name
        private without_logging
      end

      def provides_callbacks_define_wrapper(name, without_logging)
        make_public = public_method_defined?(name)
        define_method(name) do |*args|
          if defined?(logger)
            logger.debug("#{self.class.name}/#{__id__} received callback " \
                         ":#{name}.")
          end
          send(without_logging, *args)
          self
        end
        private name unless make_public
      end
    end
  end
end
