# frozen_string_literal: true

require 'spec_helper_acceptance'

describe 'networkmanager class' do
  let(:manifest) do
    <<~PUPPET
      class { 'networkmanager':
        manage_nm_package => true,
        manage_nm_service => true,
        service_ensure    => 'running',
        service_enable    => true,
      }
    PUPPET
  end

  it 'applies idempotently' do
    apply_manifest(manifest, catch_failures: true)
    apply_manifest(manifest, catch_changes: true)
  end

  describe package('NetworkManager') do
    it { is_expected.to be_installed }
  end

  describe service('NetworkManager') do
    it { is_expected.to be_running }
    it { is_expected.to be_enabled }
  end

  context 'with wait-online service management enabled' do
    # Starting wait-online blocks until the host is online, which depends on the
    # test environment. Stopping the oneshot unit does not affect networking.
    let(:manifest) do
      <<~PUPPET
        class { 'networkmanager':
          manage_nm_service_wait_online => true,
          service_wait_online_ensure    => 'stopped',
        }
      PUPPET
    end

    it 'applies idempotently' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)
    end

    describe service('NetworkManager-wait-online') do
      it { is_expected.not_to be_running }
      it { is_expected.to be_enabled }
    end
  end

  context 'with configuration management enabled' do
    # Use a drop-in and leave the service unmanaged so NetworkManager is not
    # restarted on the test host.
    let(:config_file) { '/etc/NetworkManager/conf.d/99-puppet-acceptance.conf' }
    let(:manifest) do
      <<~PUPPET
        class { 'networkmanager':
          manage_nm_service => false,
          manage_nm_config  => true,
          config_file       => '#{config_file}',
          config_file_mode  => '0640',
          options           => {
            'logging' => {
              'level' => 'INFO',
            },
          },
        }
      PUPPET
    end

    after do
      shell("rm -f '#{config_file}'")
    end

    it 'manages a drop-in that NetworkManager loads' do
      apply_manifest(manifest, catch_failures: true)
      apply_manifest(manifest, catch_changes: true)

      expect(file(config_file)).to be_file
      expect(file(config_file)).to be_mode 640
      expect(file(config_file)).to be_owned_by 'root'
      expect(file(config_file)).to be_grouped_into 'root'
      expect(file(config_file).content).to match(%r{^\[logging\]$})
      expect(file(config_file).content).to match(%r{^level=})

      expect(shell('NetworkManager --print-config').stdout).to include(config_file)
    end
  end
end
