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
  #     end
  #
  #     callback(:it_was_done) do |some_arg:|
  #       puts "Yay! #{some_arg}"
  #     end
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
  #
  # Callbacks can be given to collaborating objects, but the actual methods are
  # defined as private methods. This allows the object to control which other
  # objects are able to invoke the callbacks (at least to the extent that Ruby
  # lets you do so.)
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
      # Defines a callback method on the class
      #
      # The provided block will be used to define an instance method. This
      # behaves similarly to #define_method, however it will ensure that
      # callbacks are logged if the object has a #logger method defined.
      #
      # @param name [Symbol] The name of the callback
      # @param block [Proc] The code that will be executed in the context of the
      #   object when the callback is invoked.
      # @return [self]
      def callback(name, &block)
        define_method("#{name}_without_logging", &block)
        define_method(name) do |*args|
          if defined?(logger)
            logger.debug("#{self.class.name}/#{__id__} received callback " \
                         ":#{name}.")
          end
          send("#{name}_without_logging", *args)
          self
        end
        private name
        self
      end
    end
  end
end
