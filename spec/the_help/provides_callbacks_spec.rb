# frozen_string_literal: true

RSpec.describe TheHelp::ProvidesCallbacks do
  describe 'an instance of an including class' do
    subject {
      c = Class.new do
        include TheHelp::ProvidesCallbacks

        attr_accessor :collaborator

        def initialize(collaborator)
          self.collaborator = collaborator
        end

        def do_something
          collaborator.do_something(done: callback(:my_callback))
        end

        callback :my_callback do |something:|
          collaborator.callback_received(something)
        end
      end
      c.new(collaborator)
    }

    let(:collaborator) {
      double('collaborator', callback_received: nil).tap do |c|
        allow(c).to receive(:do_something) { |done:|
          done.call(something: 123)
        }
      end
    }

    it 'can allow a collaborator to call its callbacks' do
      subject.do_something
      expect(collaborator).to have_received(:callback_received).with(123)
    end

    it 'does not expose callbacks as public methods' do
      expect { subject.my_callback }.to raise_error(NoMethodError)
    end

    context 'when the including class has a #logger method' do
      before(:each) do
        subject.class.class_eval do
          attr_accessor :logger
        end

        subject.logger = logger
      end

      let(:logger) {
        instance_double('Logger', debug: nil)
      }

      it 'logs the callback access as a debug message' do
        subject.do_something
        expect(logger)
          .to have_received(:debug)
                .with("#{subject.inspect} received callback :my_callback.")
      end
    end
  end
end
