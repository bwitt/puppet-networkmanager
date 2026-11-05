# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'networkmanager_connection ethernet resource' do
  # The device does not exist, so the profile can never be activated.
  let(:test_profile) do
    {
      connection: 'puppet-acceptance-eth',
      interface: 'nmtest0',
    }
  end

  let(:networkmanager_manifest) do
    <<~PUPPET
      class { 'networkmanager':
        manage_nm_package => true,
        manage_nm_service => true,
      }
    PUPPET
  end

  let(:minimal_manifest) do
    <<~PUPPET
      #{networkmanager_manifest}

      networkmanager_connection { '#{test_profile[:connection]}':
        ensure  => present,
        type    => '802-3-ethernet',
        device  => '#{test_profile[:interface]}',
        require => Service['NetworkManager'],
      }
    PUPPET
  end

  let(:initial_manifest) do
    <<~PUPPET
      #{networkmanager_manifest}

      networkmanager_connection { '#{test_profile[:connection]}':
        ensure         => present,
        type           => '802-3-ethernet',
        device         => '#{test_profile[:interface]}',
        ipv4_method    => manual,
        ipv4_addresses => ['192.0.2.30/24'],
        ipv4_gateway   => '192.0.2.1',
        ipv4_dns       => ['192.0.2.53'],
        ipv6_method    => manual,
        ipv6_addresses => ['2001:db8::30/64'],
        ipv6_gateway   => '2001:db8::1',
        ipv6_dns       => ['2001:db8::53'],
        ipv6_routes    => [
          {
            destination => '2001:db8:100::/64',
            next_hop    => '2001:db8::1',
            metric      => 100,
            source      => '2001:db8::30',
          },
        ],
        reapply        => false,
        require        => Service['NetworkManager'],
      }
    PUPPET
  end

  let(:updated_manifest) do
    <<~PUPPET
      #{networkmanager_manifest}

      networkmanager_connection { '#{test_profile[:connection]}':
        ensure         => present,
        type           => '802-3-ethernet',
        device         => '#{test_profile[:interface]}',
        ipv4_method    => manual,
        ipv4_addresses => ['192.0.2.40/24'],
        ipv4_gateway   => '192.0.2.254',
        ipv4_dns       => ['192.0.2.53'],
        ipv6_method    => manual,
        ipv6_addresses => ['2001:db8::40/64'],
        ipv6_gateway   => '2001:db8::fe',
        ipv6_dns       => ['2001:db8::53', '2001:db8::54'],
        ipv6_routes    => [
          {
            destination => '2001:db8:200::/64',
            next_hop    => '2001:db8::fe',
            metric      => 200,
            source      => '2001:db8::40',
          },
        ],
        reapply        => false,
        require        => Service['NetworkManager'],
      }
    PUPPET
  end

  # Disable escaping so IPv6 colons are not returned as '\:'.
  def nm_value(field)
    shell("nmcli -e no --get-values #{field} connection show '#{test_profile[:connection]}'").stdout.strip
  end

  before do
    apply_manifest(networkmanager_manifest, catch_failures: true)
    shell("nmcli connection delete '#{test_profile[:connection]}'", acceptable_exit_codes: [0, 10])
  end

  after do
    shell("nmcli connection delete '#{test_profile[:connection]}'", acceptable_exit_codes: [0, 10])
  end

  context 'when creating a profile with default methods' do
    it 'creates the requested profile idempotently' do
      expect(test_profile[:interface].length).to be <= 15

      apply_manifest(minimal_manifest, catch_failures: true)
      apply_manifest(minimal_manifest, catch_changes: true)

      expect(nm_value('connection.type')).to eq('802-3-ethernet')
      expect(nm_value('connection.interface-name')).to eq(test_profile[:interface])
      expect(nm_value('ipv4.method')).to eq('auto')
      expect(nm_value('ipv6.method')).to eq('auto')
      expect(nm_value('GENERAL.STATE')).to be_empty
    end
  end

  context 'when creating a dual-stack profile' do
    it 'creates the requested profile idempotently' do
      apply_manifest(initial_manifest, catch_failures: true)
      apply_manifest(initial_manifest, catch_changes: true)

      expect(nm_value('ipv4.addresses')).to eq('192.0.2.30/24')
      expect(nm_value('ipv4.gateway')).to eq('192.0.2.1')
      expect(nm_value('ipv6.method')).to eq('manual')
      expect(nm_value('ipv6.addresses')).to eq('2001:db8::30/64')
      expect(nm_value('ipv6.gateway')).to eq('2001:db8::1')
      expect(nm_value('ipv6.dns')).to include('2001:db8::53')

      routes = nm_value('ipv6.routes')
      expect(routes).to include('2001:db8:100::/64')
      expect(routes).to include('2001:db8::1')
      expect(routes).to match(%r{\b100\b})
      expect(routes).to include('src=2001:db8::30')

      expect(nm_value('GENERAL.STATE')).to be_empty
    end
  end

  context 'when updating a dual-stack profile' do
    it 'updates the requested profile idempotently' do
      apply_manifest(initial_manifest, catch_failures: true)
      apply_manifest(updated_manifest, catch_failures: true)
      apply_manifest(updated_manifest, catch_changes: true)

      expect(nm_value('ipv4.addresses')).to eq('192.0.2.40/24')
      expect(nm_value('ipv4.gateway')).to eq('192.0.2.254')
      expect(nm_value('ipv6.addresses')).to eq('2001:db8::40/64')
      expect(nm_value('ipv6.gateway')).to eq('2001:db8::fe')
      expect(nm_value('ipv6.dns')).to include('2001:db8::53')
      expect(nm_value('ipv6.dns')).to include('2001:db8::54')

      routes = nm_value('ipv6.routes')
      expect(routes).to include('2001:db8:200::/64')
      expect(routes).to include('src=2001:db8::40')
      expect(routes).not_to include('2001:db8:100::/64')
    end
  end
end
