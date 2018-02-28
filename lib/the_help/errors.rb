# frozen_string_literal: true

module TheHelp
  module Errors
    class AbstractClassError < StandardError; end
    class ServiceNotImplementedError < StandardError; end
    class NotAuthorizedError < RuntimeError; end
  end
end
