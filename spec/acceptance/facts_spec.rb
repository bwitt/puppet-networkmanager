# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'networkmanager facts' do
  # The device does not exist, so the profile can never be activated.
  let(:connection) { 'puppet-acceptance-facts' }

  let(:manifest) do
    <<~PUPPET
      class { 'networkmanager':
        manage_nm_package => true,
        manage_nm_service => true,
      }

      networkmanager_connection { '#{connection}':
        ensure         => present,
        type           => '802-3-ethernet',
        device         => 'nmtest1',
        ipv4_method    => manual,
        ipv4_addresses => ['192.0.2.50/24'],
        ipv6_method    => manual,
        ipv6_addresses => ['2001:db8::50/64'],
        require        => Service['NetworkManager'],
      }
    PUPPET
  end

  before do
    apply_manifest(manifest, catch_failures: true)
  end

  after do
    shell("nmcli connection delete '#{connection}'", acceptable_exit_codes: [0, 10])
  end

  it 'reports the NetworkManager version' do
    expect(fact('nm_version')).to eq(shell('NetworkManager --version').stdout.strip)
  end

  it 'reports networking as enabled' do
    expect(fact('nm_network')).to eq('enabled')
  end

  it 'reports network connectivity' do
    expect(fact('nm_network_connectivity')).to match(%r{\A(none|portal|limited|full|unknown)\z})
  end

  it 'reports the loopback device' do
    expect(fact('nm_all_devices')).to include('lo' => include('type' => 'loopback'))
  end

  it 'reports the inactive profile with its addresses' do
    expect(fact('nm_all_connections')).to include(
      connection => include(
        'type' => '802-3-ethernet',
        'active' => false,
        'ipv4' => include('method' => 'manual', 'address' => ['192.0.2.50/24']),
        'ipv6' => include('method' => 'manual', 'address' => ['2001:db8::50/64']),
      ),
    )
  end

  it 'does not report the inactive profile as active' do
    expect(fact('nm_active_connections') || {}).not_to have_key(connection)
  end
end
