# frozen_string_literal: true

RSpec.describe TheHelp::ServiceCaller do
  let(:includer) {
    Class.new do
      include TheHelp::ServiceCaller

      attr_accessor :service, :service_context, :service_logger, :arg1, :arg2
      attr_accessor :result

      def initialize(**args)
        args.each do |(k, v)|
          send("#{k}=", v)
        end
      end

      def do_something
        call_service(service, arg1: arg1, arg2: arg2)
      end

      def do_something_with_block
        call_service(service, arg1: arg1, arg2: arg2) { |r| self.result = r }
      end
    end
  }

  subject {
    includer.new(
      service: service,
      service_context: service_context,
      service_logger: service_logger,
      arg1: arg1,
      arg2: arg2
    )
  }

  let(:service) { instance_double('Proc', :service, call: nil) }
  let(:service_context) { double('context') }
  let(:service_logger) { double('logger') }
  let(:arg1) { double('arg1') }
  let(:arg2) { double('arg2') }

  it "calls the specified service using the including module's " \
     'service_context and service_logger' do
    subject.do_something
    expect(service).to have_received(:call).with(
      context: service_context,
      logger: service_logger,
      arg1: arg1,
      arg2: arg2
    )
  end

  it 'sends the provided block to the service' do
    allow(service).to receive(:call).and_yield(42)
    subject.do_something_with_block
    expect(subject.result).to eq 42
  end
end
