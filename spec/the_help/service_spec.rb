# frozen_string_literal: true

RSpec.describe TheHelp::Service do
  subject { -> { described_class.call(**service_args) } }

  let(:service_args) {
    {
      context: authorization_context,
      logger: logger
    }
  }

  let(:authorization_context) {
    double(:authorization_context)
  }

  let(:logger) {
    instance_double('Logger',
                    fatal: nil, error: nil, warn: nil, info: nil, debug: nil)
  }

  it 'raises an AbstractClassError when called directly' do
    expect { subject.call }.to raise_error(TheHelp::AbstractClassError)
  end

  describe 'a subclass of Service' do
    subject { -> { subclass.call(**service_args) } }

    context 'when the subclass does not define a "main" routine' do
      let(:subclass) { Class.new(described_class) }

      it 'raises a ServiceNotImplementedError' do
        expect { subject.call }
          .to raise_error(TheHelp::ServiceNotImplementedError)
      end
    end

    context 'when the subclass defines a main routine' do
      let(:subclass) {
        Class.new(described_class) do
          # because otherwise it would be empty when defined by Class.new
          def self.name
            'TestSubclass'
          end

          main do
            collaborator.some_message
          end

          private

          def collaborator
            CollaboratorStub
          end
        end
      }

      let!(:collaborator) {
        class_double('CollaboratorStub').tap do |c|
          c.as_stubbed_const
          allow(c).to receive(:some_message)
        end
      }

      shared_examples_for :it_is_not_authorized do
        context 'when no not_authorized callback is specified' do
          it 'does not execute the main routine' do
            expect { subject.call }.to raise_error(TheHelp::NotAuthorizedError)
            expect(collaborator).not_to have_received(:some_message)
          end

          it 'raises a NotAuthorizedError' do
            expect { subject.call }.to raise_error(TheHelp::NotAuthorizedError)
          end

          it 'logs the unauthorized service call' do
            expect { subject.call }.to raise_error(TheHelp::NotAuthorizedError)
            expect(logger)
              .to have_received(:warn)
                    .with("Unauthorized attempt to access #{subclass.name} " \
                          "as #{authorization_context.inspect}")
          end
        end

        context 'when a not_authorized callback is specified' do
          let(:not_authorized) {
            instance_double('Proc', 'not_authorized', call: nil)
          }

          before(:each) do
            service_args[:not_authorized] = not_authorized
          end

          it 'does not execute the main routine' do
            subject.call
            expect(collaborator).not_to have_received(:some_message)
          end

          it 'calls the not_authorized callback with the service class ' \
             'and context' do
            subject.call
            expect(not_authorized)
              .to have_received(:call).with(service: subclass,
                                            context: authorization_context)
          end

          it 'logs the unauthorized service call' do
            subject.call
            expect(logger)
              .to have_received(:warn)
                    .with("Unauthorized attempt to access #{subclass.name} " \
                          "as #{authorization_context.inspect}")
          end
        end
      end

      context 'when no authorization is specified' do
        it_behaves_like :it_is_not_authorized
      end

      context 'when authorization is specified as a block' do
        let(:subclass) {
          Class.new(described_class) do
            # because otherwise it would be empty when defined by Class.new
            def self.name
              'TestSubclass'
            end

            authorization_policy do
              context.meets_some_criteria?
            end

            main do
              collaborator.some_message
            end

            private

            def collaborator
              CollaboratorStub
            end
          end
        }

        context 'when the context is authorized' do
          before(:each) do
            allow(authorization_context)
              .to receive(:meets_some_criteria?).and_return(true)
          end

          it 'executes the main routine' do
            subject.call
            expect(collaborator).to have_received(:some_message)
          end

          it 'logs that the service was called' do
            subject.call
            expect(logger)
              .to have_received(:info)
                    .with("Service call to #{subclass.name} for " \
                          "#{authorization_context.inspect}")
          end

          it 'returns itself' do
            expect(subject.call).to eq subclass
          end

          context 'when called with a block' do
            let(:effective_subclass) { subclass }

            subject {
              -> {
                effective_subclass.call(**service_args) do |result|
                  result_handler.call(result)
                end
              }
            }

            let(:result_handler) { instance_double('Proc', :result, call: nil) }

            context 'when the service sets the result internally' do
              let(:effective_subclass) {
                Class.new(subclass) do
                  main do
                    collaborator.some_message
                    self.result = :expected_result
                  end
                end
              }

              it 'yields the result to the provided block' do
                subject.call
                expect(result_handler)
                  .to have_received(:call).with(:expected_result)
              end
            end

            context 'when the service does not set a result internally' do
              it 'raises  TheHelp::NoResultError' do
                expect { subject.call }.to raise_error(TheHelp::NoResultError)
              end

              it 'does not try to call the provided block' do
                subject.call rescue nil
                expect(result_handler).not_to have_received(:call)
              end
            end
          end
        end

        context 'when the context is not authorized' do
          before(:each) do
            allow(authorization_context)
              .to receive(:meets_some_criteria?).and_return(false)
          end

          it_behaves_like :it_is_not_authorized
        end
      end
    end

    shared_examples_for :it_uses_the_specified_input_value do
      let(:collaborator) {
        double('collaborator input', some_message: nil)
      }

      before(:each) do
        service_args[:foo] = collaborator
      end

      it 'makes the specified input value available to the instance' do
        subject.call
        expect(collaborator).to have_received(:some_message)
      end
    end

    context 'when an input is defined with no default value' do
      let(:subclass) {
        Class.new(described_class) do
          # because otherwise it would be empty when defined by Class.new
          def self.name
            'TestSubclass'
          end

          input :foo

          authorization_policy allow_all: true

          main do
            foo.some_message
          end
        end
      }

      it 'requires the input to be specified at initialization' do
        expect { subclass.new(context: authorization_context) }
          .to raise_error(ArgumentError, /Missing required .*foo/)
      end

      it_behaves_like :it_uses_the_specified_input_value
    end

    context 'when an input is defined with a default value' do
      let(:subclass) {
        Class.new(described_class) do
          # because otherwise it would be empty when defined by Class.new
          def self.name
            'TestSubclass'
          end

          input :foo, default: DefaultCollaborator

          authorization_policy allow_all: true

          main do
            foo.some_message
          end
        end
      }

      let!(:default_collaborator) {
        class_double('DefaultCollaborator').tap do |c|
          c.as_stubbed_const
          allow(c).to receive(:some_message)
        end
      }

      context 'when initialized with a specified value' do
        it_behaves_like :it_uses_the_specified_input_value
      end

      context 'when initialized without a specified value' do
        it 'uses the default value' do
          subject.call
          expect(default_collaborator).to have_received(:some_message)
        end
      end
    end
  end

  context 'a subclass of a subclass of Service' do
    let(:intermediate_class) {
      Class.new(described_class) do
        # because otherwise it would be empty when defined by Class.new
        def self.name
          'TestSubclass'
        end

        input :collaborator
        input :some_value, default: 1
        input :some_other_value

        main do
          collaborator.message_one
        end
      end
    }

    let(:subclass) {
      Class.new(intermediate_class) do
        # because otherwise it would be empty when defined by Class.new
        def self.name
          'TestSubclass2'
        end

        input :collaborator_2
        input :some_value, default: 2
        input :some_other_value, default: :foo

        authorization_policy allow_all: true

        main do
          super()
          collaborator.message_two(some_other_value)
          collaborator_2.a_message(some_value)
        end
      end
    }

    let(:collaborator) {
      double('collaborator', message_one: nil, message_two: nil)
    }

    let(:collaborator_2) {
      double('collaborator', a_message: nil)
    }

    subject { -> { subclass.call(**service_args) } }

    before(:each) do
      service_args[:collaborator] = collaborator
      service_args[:collaborator_2] = collaborator_2
    end

    it 'preserves original inputs' do
      subject.call
      expect(collaborator).to have_received(:message_two)
    end

    it 'still requires original inputs that have no default' do
      service_args.delete(:collaborator)
      expect { subclass.new(**service_args) }
        .to raise_error(ArgumentError, /Missing required .*collaborator/)
    end

    it 'can add new inputs' do
      subject.call
      expect(collaborator_2).to have_received(:a_message)
    end

    it 'does not add the new inputs to the intermediate class' do
      service_args[:some_other_value] = 1
      expect { intermediate_class.new(**service_args) }
        .to raise_error(NoMethodError, /collaborator_2/)
    end

    it 'can override the default value of an existing input' do
      subject.call
      expect(collaborator_2).to have_received(:a_message).with(2)
    end

    it 'can add a default value to an existing input' do
      subject.call
      expect(collaborator).to have_received(:message_two).with(:foo)
    end

    it 'can call the original main routine with "super()"' do
      subject.call
      expect(collaborator).to have_received(:message_one)
    end
  end
end
