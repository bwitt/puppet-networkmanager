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

  # Attribute values are Puppet code.
  let(:dual_stack) do
    {
      ipv4_method: 'manual',
      ipv4_addresses: "['192.0.2.30/24', '192.0.2.31/24']",
      ipv4_gateway: "'192.0.2.1'",
      ipv4_dns: "['192.0.2.53']",
      ipv4_routes: <<~ROUTES.chomp,
        [
          { destination => '198.51.100.0/24', next_hop => '192.0.2.1', metric => 100, source => '192.0.2.31' },
          { destination => '203.0.113.0/24', metric => 150, source => '192.0.2.30' },
        ]
      ROUTES
      ipv6_method: 'manual',
      ipv6_addresses: "['2001:db8::30/64', '2001:db8::31/64']",
      ipv6_gateway: "'2001:db8::1'",
      ipv6_dns: "['2001:db8::53']",
      ipv6_routes: <<~ROUTES.chomp,
        [
          { destination => '2001:db8:100::/64', next_hop => '2001:db8::1', metric => 100, source => '2001:db8::30' },
          { destination => '2001:db8:300::/64', metric => 150, source => '2001:db8::31' },
        ]
      ROUTES
    }
  end

  def initial_manifest
    profile_manifest(dual_stack)
  end

  def updated_manifest
    profile_manifest(
      dual_stack.merge(
        ipv4_addresses: "['192.0.2.40/24']",
        ipv4_gateway: "'192.0.2.254'",
        ipv4_routes: "[{ destination => '198.51.100.0/24', next_hop => '192.0.2.254', metric => 200, source => '192.0.2.40' }]",
        ipv6_addresses: "['2001:db8::40/64']",
        ipv6_gateway: "'2001:db8::fe'",
        ipv6_dns: "['2001:db8::53', '2001:db8::54']",
        ipv6_routes: "[{ destination => '2001:db8:200::/64', next_hop => '2001:db8::fe', metric => 200, source => '2001:db8::40' }]",
      ),
    )
  end

  def profile_manifest(attributes, name: test_profile[:connection])
    lines = attributes.map { |key, value| "  #{key} => #{value}," }

    <<~PUPPET
      #{networkmanager_manifest}

      networkmanager_connection { '#{name}':
        ensure  => present,
        type    => '802-3-ethernet',
        device  => '#{test_profile[:interface]}',
        reapply => false,
        require => Service['NetworkManager'],
      #{lines.join("\n")}
      }
    PUPPET
  end

  # Disable escaping so IPv6 colons are not returned as '\:'.
  def nm_value(field, name: test_profile[:connection])
    shell("nmcli -e no --get-values #{field} connection show '#{name}'").stdout.strip
  end

  # Deletes every profile with this name, including duplicates.
  def delete_profiles(name)
    shell('nmcli -t -e no -f UUID,NAME connection show').stdout.each_line do |line|
      uuid, profile = line.strip.split(':', 2)
      shell("nmcli connection delete uuid '#{uuid}'") if profile == name
    end
  end

  def profile_count(name)
    shell('nmcli -t -e no -f NAME connection show').stdout.lines.map(&:strip).count(name)
  end

  before do
    apply_manifest(networkmanager_manifest, catch_failures: true)
    delete_profiles(test_profile[:connection])
  end

  after do
    delete_profiles(test_profile[:connection])
  end

  context 'when creating a profile with default methods' do
    it 'creates the requested profile idempotently' do
      expect(test_profile[:interface].length).to be <= 15

      minimal_manifest = profile_manifest({})

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

      expect(nm_value('ipv4.addresses')).to include('192.0.2.30/24', '192.0.2.31/24')
      expect(nm_value('ipv4.gateway')).to eq('192.0.2.1')

      ipv4_routes = nm_value('ipv4.routes')
      expect(ipv4_routes).to include('198.51.100.0/24', 'src=192.0.2.31')
      expect(ipv4_routes).to include('203.0.113.0/24', 'src=192.0.2.30')
      expect(ipv4_routes).to match(%r{\b150\b})

      expect(nm_value('ipv6.method')).to eq('manual')
      expect(nm_value('ipv6.addresses')).to include('2001:db8::30/64', '2001:db8::31/64')
      expect(nm_value('ipv6.gateway')).to eq('2001:db8::1')
      expect(nm_value('ipv6.dns')).to include('2001:db8::53')

      ipv6_routes = nm_value('ipv6.routes')
      expect(ipv6_routes).to include('2001:db8:100::/64', '2001:db8::1', 'src=2001:db8::30')
      expect(ipv6_routes).to match(%r{\b100\b})
      expect(ipv6_routes).to include('2001:db8:300::/64', 'src=2001:db8::31')

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

      ipv4_routes = nm_value('ipv4.routes')
      expect(ipv4_routes).to include('198.51.100.0/24', '192.0.2.254', 'src=192.0.2.40')
      expect(ipv4_routes).not_to include('203.0.113.0/24')

      expect(nm_value('ipv6.addresses')).to eq('2001:db8::40/64')
      expect(nm_value('ipv6.gateway')).to eq('2001:db8::fe')
      expect(nm_value('ipv6.dns')).to include('2001:db8::53', '2001:db8::54')

      ipv6_routes = nm_value('ipv6.routes')
      expect(ipv6_routes).to include('2001:db8:200::/64', 'src=2001:db8::40')
      expect(ipv6_routes).not_to include('2001:db8:100::/64')
      expect(ipv6_routes).not_to include('2001:db8:300::/64')
    end
  end

  context 'when removing routes with empty arrays' do
    it 'removes the routes idempotently' do
      removed_manifest = profile_manifest(dual_stack.merge(ipv4_routes: '[]', ipv6_routes: '[]'))

      apply_manifest(initial_manifest, catch_failures: true)
      apply_manifest(removed_manifest, catch_failures: true)
      apply_manifest(removed_manifest, catch_changes: true)

      expect(nm_value('ipv4.routes')).to be_empty
      expect(nm_value('ipv6.routes')).to be_empty
      expect(nm_value('ipv4.addresses')).to include('192.0.2.30/24')
    end
  end

  context 'when an invalid change is applied to an existing profile' do
    {
      'a connected network route' => [
        { ipv4_routes: "[{ destination => '192.0.2.0/24' }]" },
        %r{declares connected network '192\.0\.2\.0/24' in ipv4_routes},
      ],
      'a default route together with a gateway' => [
        { ipv4_routes: "[{ destination => '0.0.0.0/0', next_hop => '192.0.2.1' }]" },
        %r{declares both ipv4_gateway and a default route},
      ],
      'a route source from the wrong address family' => [
        { ipv6_routes: "[{ destination => '2001:db8:100::/64', source => '192.0.2.30' }]" },
        %r{invalid ipv6 route source '192\.0\.2\.30'},
      ],
    }.each do |description, (overrides, message)|
      it "rejects #{description} and leaves the profile unchanged" do
        apply_manifest(initial_manifest, catch_failures: true)

        result = apply_manifest(profile_manifest(dual_stack.merge(overrides)), expect_failures: true)
        expect(result.stderr).to match(message)

        expect(nm_value('ipv4.routes')).to include('198.51.100.0/24', '203.0.113.0/24')
        expect(nm_value('ipv6.routes')).to include('2001:db8:100::/64', '2001:db8:300::/64')
      end
    end
  end

  context 'when creating a profile with an invalid route' do
    it 'does not leave a partial profile behind' do
      pending 'connection add runs before validation; see TODO.md item 4'

      invalid_manifest = profile_manifest(dual_stack.merge(ipv4_routes: "[{ destination => '192.0.2.0/24' }]"))

      apply_manifest(invalid_manifest, expect_failures: true)

      expect(profile_count(test_profile[:connection])).to eq 0
    end
  end

  context 'when the profile name contains a colon' do
    def colon_name
      'puppet-acceptance:eth'
    end

    after do
      delete_profiles(colon_name)
    end

    it 'creates a single profile idempotently' do
      pending 'nmcli escapes the colon in terse output; see TODO.md item 6'

      manifest = profile_manifest({ ipv4_method: 'disabled', ipv6_method: 'disabled' }, name: colon_name)

      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_failures: true)

      expect(profile_count(colon_name)).to eq 1
    end
  end
end
