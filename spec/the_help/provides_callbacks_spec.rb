# frozen_string_literal: true

RSpec.describe TheHelp::ProvidesCallbacks do
  describe 'an instance of an including class' do
    subject {
      c = Class.new do
        include TheHelp::ProvidesCallbacks

        def self.name
          'TestClassThingy'
        end

        attr_accessor :collaborator

        def initialize(collaborator)
          self.collaborator = collaborator
        end

        def do_something
          collaborator.do_something(done: callback(:my_callback))
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

    shared_examples_for :it_allows_a_collaborator_to_call_its_callbacks do
      specify do
        subject.do_something
        expect(collaborator).to have_received(:callback_received).with(123)
      end
    end

    shared_examples_for :it_does_not_expose_callback_as_public_method do
      specify do
        expect { subject.my_callback }.to raise_error(NoMethodError)
      end
    end

    shared_examples_for :it_logs_the_callback_access do
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
          expect(logger).to(
            have_received(:debug)
            .with("#{subject.class.name}/#{subject.__id__} received callback " \
                  ':my_callback.')
          )
        end
      end
    end

    context 'when the callback is defined as a block' do
      before do
        subject.class.class_eval do
          callback :my_callback do |something:|
            collaborator.callback_received(something)
          end
        end
      end

      it_behaves_like :it_allows_a_collaborator_to_call_its_callbacks
      it_behaves_like :it_does_not_expose_callback_as_public_method
      it_behaves_like :it_logs_the_callback_access
    end

    context 'when the callback is defined as a private method' do
      before do
        subject.class.class_eval do
          private

          def my_callback(something:)
            collaborator.callback_received(something)
          end
          callback :my_callback
        end
      end

      it_behaves_like :it_allows_a_collaborator_to_call_its_callbacks
      it_behaves_like :it_does_not_expose_callback_as_public_method
      it_behaves_like :it_logs_the_callback_access
    end

    context 'when the callback is defined as a public method' do
      before do
        subject.class.class_eval do
          def my_callback(something:)
            collaborator.callback_received(something)
          end
          callback :my_callback
        end
      end

      it_behaves_like :it_allows_a_collaborator_to_call_its_callbacks
      it_behaves_like :it_logs_the_callback_access

      it 'retains the public scope of the callback method' do
        expect { subject.my_callback(something: 123) }
          .not_to raise_error
      end
    end
  end
end
