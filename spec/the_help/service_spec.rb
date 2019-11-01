# frozen_string_literal: true

RSpec.describe TheHelp::Service do
  subject { described_class.new(**service_args) }

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

  describe TheHelp::Service::Result do
    subject { described_class.new }

    context 'when no result has been specified' do
      it { should be_pending }
      it { should_not be_success }
      it { should_not be_error }

      it 'has a nil value' do
        expect(subject.value).to be_nil
      end

      it 'raises an exception when #value! is called' do
        expect { subject.value! }.to raise_error(TheHelp::NoResultError)
      end
    end

    context 'when a success result has been specified' do
      before(:each) { subject.success 'a result' }

      it { should_not be_pending }
      it { should be_success }
      it { should_not be_error }

      it 'has the value' do
        expect(subject.value).to eq 'a result'
      end

      it 'returns the value when #value! is called' do
        expect(subject.value!).to eq 'a result'
      end
    end

    context 'when an error result has been specified' do
      before(:each) { subject.error 'an error' }

      it { should_not be_pending }
      it { should_not be_success }
      it { should be_error }

      it 'has the value' do
        expect(subject.value).to eq 'an error'
      end

      it 'raises an exception when #value! is called' do
        expect { subject.value! }.to raise_error(TheHelp::ResultError, 'an error')
      end
    end

    context 'when an error result has been specified as an exception' do
      before(:each) { subject.error ArgumentError.new('foo') }

      it { should_not be_pending }
      it { should_not be_success }
      it { should be_error }

      it 'has the value' do
        expect(subject.value).to be_a(ArgumentError)
      end

      it 'raises an exception when #value! is called' do
        expect { subject.value! }.to raise_error(ArgumentError, 'foo')
      end
    end

    context 'when an error result has been specified as an exception raised in a block' do
      before(:each) { subject.error { raise ArgumentError.new('foo') } }
      let!(:error_line) { (__LINE__ - 1).to_s }

      it { should_not be_pending }
      it { should_not be_success }
      it { should be_error }

      it 'has the value' do
        expect(subject.value).to be_a(ArgumentError)
      end

      it 'has a bactrace pointing to where the error was originally raised' do
        callsite = subject.value.backtrace.first
        filename, line_no, _ = *callsite.split(':')
        expect(filename).to eq __FILE__
        expect(line_no).to eq error_line
      end

      it 'raises an exception when #value! is called' do
        expect { subject.value! }.to raise_error(ArgumentError, 'foo')
      end
    end
  end

  describe 'a service that calls another service and executes `stop!` in a ' \
           'callback' do
    let(:service_a) {
      Class.new(described_class) do
        def self.name
          'OuterService'
        end

        input :collaborator
        input :modifier

        authorization_policy allow_all: true

        main do
          call_service(collaborator,
                       and_run: method(:stop!),
                       modifier: modifier)
          run_callback(modifier, :outer_result)
          result.success(:outer_result)
        end
      end
    }

    let(:service_b) {
      Class.new(described_class) do
        def self.name
          'InnerService'
        end

        input :and_run
        input :modifier

        authorization_policy allow_all: true

        main do
          run_callback(and_run)
          run_callback(modifier, :inner_result)
          result.success(:inner_result)
        end
      end
    }

    let(:modifier) { instance_double('Proc', call: nil) }

    subject {
      service_a.new(collaborator: service_b, modifier: modifier, **service_args)
    }

    it 'stops the outer service' do
      subject.call
      expect(modifier).not_to have_received(:call).with(:outer_result)
    end

    it 'does not stop the inner service' do
      subject.call
      expect(modifier).to have_received(:call).with(:inner_result)
    end
  end

  describe 'a subclass of Service' do
    subject { subclass.new(**service_args) }

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
            result.success(:a_result)
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
            expect(logger).to(
              have_received(:warn)
              .with(
                match(
                  Regexp.new("Unauthorized attempt to access " \
                             "#{subclass.name}/\\w+ " \
                             "as #{authorization_context.inspect}")
                )
              )
            )
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
            expect(logger).to(
              have_received(:warn)
              .with(
                match(
                  Regexp.new("Unauthorized attempt to access " \
                             "#{subclass.name}/\\w+ " \
                             "as #{authorization_context.inspect}")
                )
              )
            )
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
            subject.call rescue nil
            expect(collaborator).to have_received(:some_message)
          end

          it 'logs that the service was called' do
            subject.call rescue nil
            expect(logger).to(
              have_received(:debug)
              .with(
                match(
                  Regexp.new("Service call to " \
                             "#{subclass.name}/\\w+ " \
                             "for #{authorization_context.inspect}")
                )
              )
            )
          end

          context 'when the service does not set a success or error result' do
            it 'raises an exception' do
              expect { subject.call }
                .to raise_error(TheHelp::Errors::NoResultError)
            end
          end

          context 'when the service sets a result internally' do
            let(:effective_subclass) {
              Class.new(subclass) do
                main do
                  collaborator.some_message
                  result.success(:expected_result)
                end
              end
            }

            subject { effective_subclass.new(**service_args) }

            it 'returns the result' do
              expect(subject.call.value).to eq :expected_result
            end
          end

          context 'when called with a block' do
            let(:effective_subclass) { subclass }

            subject { effective_subclass.new(**service_args) }

            context 'when the service sets the result internally' do
              let(:effective_subclass) {
                Class.new(subclass) do
                  main do
                    collaborator.some_message
                    result.success(:expected_result)
                  end
                end
              }

              it 'yields the result to the provided block' do
                result = nil
                subject.call { |r|  result = r.value }
                expect(result).to eq :expected_result
              end

              it 'returns the result of the block' do
                result = subject.call { |_r| 'the value' }
                expect(result).to eq 'the value'
              end
            end

            context 'when the service does not set a result internally' do
              it 'raises  TheHelp::NoResultError' do
                expect { subject.call { |r| r } }
                  .to raise_error(TheHelp::NoResultError)
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
            result.success(:some_result)
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
            result.success(:some_result)
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
          result.success(:some_result)
        end
      end
    }

    let(:collaborator) {
      double('collaborator', message_one: nil, message_two: nil)
    }

    let(:collaborator_2) {
      double('collaborator', a_message: nil)
    }

    subject { subclass.new(**service_args) }

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
