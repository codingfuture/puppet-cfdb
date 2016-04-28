require 'spec_helper'
describe 'cfdb' do

  context 'with defaults for all parameters' do
    it { should contain_class('cfdb') }
  end
end
