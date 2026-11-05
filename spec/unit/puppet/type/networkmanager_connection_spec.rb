# frozen_string_literal: true

require 'spec_helper'
require 'puppet/type/networkmanager_connection'

RSpec.describe 'the networkmanager_connection type' do
  it 'loads' do
    expect(Puppet::Type.type(:networkmanager_connection)).not_to be_nil
  end

  # nmcli reports aliased types by their full setting names.
  {
    'ethernet' => '802-3-ethernet',
    '802-3-ethernet' => '802-3-ethernet',
    'wifi' => '802-11-wireless',
    '802-11-wireless' => '802-11-wireless',
    'bridge' => 'bridge',
  }.each do |type, nmcli_type|
    it "canonicalizes type #{type} to #{nmcli_type}" do
      resource = Puppet::Type.type(:networkmanager_connection).new(name: 'lab-lan', type: type)

      expect(resource.rsapi_canonicalized_target_state[:type]).to eq(nmcli_type)
    end
  end
end
