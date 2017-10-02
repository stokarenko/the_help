module TheHelp
  module ProvidesCallbacks
    def self.included(other)
      other.class_eval do
        extend TheHelp::ProvidesCallbacks::ClassMethods
        alias callback method
      end
    end

    module ClassMethods
      def callback(name, &block)
        define_method("#{name}_without_logging", &block)
        define_method(name) do
          if defined?(logger)
            logger.debug("#{inspect} received callback :#{name}.")
          end
          send("#{name}_without_logging")
        end
        private name
      end
    end
  end
end
