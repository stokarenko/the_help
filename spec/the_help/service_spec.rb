require 'the_help/service'

RSpec.describe TheHelp::Service do
  subject { described_class.new(**service_args) }

  let(:service_args) {
    { context: authorization_context }
  }

  let(:authorization_context) {
    double(:authorization_context)
  }

  it 'raises an AbstractClassError when called directly' do
    expect { subject.call }.to raise_error(TheHelp::AbstractClassError)
  end

  describe 'a subclass of Service' do
    subject { subclass.new(**service_args) }

    context 'when the subclass does not define a "main" routine' do
      let(:subclass) { Class.new(described_class) }

      it 'raises a ServiceNotImplementedError' do
        expect { subject.call }.to raise_error(TheHelp::ServiceNotImplementedError)
      end
    end

    context 'when the subclass defines a main routine' do
      let(:subclass) {
        Class.new(described_class) do
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
            subject.call rescue nil
            expect(collaborator).not_to have_received(:some_message)
          end

          it 'raises a NotAuthorizedError' do
            expect { subject.call }.to raise_error(TheHelp::NotAuthorizedError)
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

          it 'calls the not_authorized callback with the service class and context' do
            subject.call
            expect(not_authorized)
              .to have_received(:call).with(service: subclass,
                                            context: authorization_context)
          end
        end
      end

      context 'when no authorization is specified' do
        it_behaves_like :it_is_not_authorized
      end

      context 'when authorization is specified as a block' do
        let(:subclass) {
          Class.new(described_class) do
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

          it 'returns itself' do
            expect(subject.call).to eq subject
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
  end
end