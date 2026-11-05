# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'networkmanager_connection type aliases' do
  # The device does not exist, so the profile can never be activated.
  let(:test_profile) do
    {
      connection: 'puppet-acceptance-alias',
      interface: 'nmtest2',
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

  let(:manifest) do
    <<~PUPPET
      #{networkmanager_manifest}

      networkmanager_connection { '#{test_profile[:connection]}':
        ensure      => present,
        type        => ethernet,
        device      => '#{test_profile[:interface]}',
        ipv4_method => disabled,
        ipv6_method => disabled,
        require     => Service['NetworkManager'],
      }
    PUPPET
  end

  before do
    apply_manifest(networkmanager_manifest, catch_failures: true)
    shell("nmcli connection delete '#{test_profile[:connection]}'", acceptable_exit_codes: [0, 10])
  end

  after do
    shell("nmcli connection delete '#{test_profile[:connection]}'", acceptable_exit_codes: [0, 10])
  end

  it 'creates an ethernet profile idempotently' do
    expect(test_profile[:interface].length).to be <= 15

    apply_manifest(manifest, catch_failures: true)
    apply_manifest(manifest, catch_changes: true)

    connection_type = shell("nmcli --get-values connection.type connection show '#{test_profile[:connection]}'").stdout
    expect(connection_type).to match(%r{\A802-3-ethernet\s*\z})
  end
end
