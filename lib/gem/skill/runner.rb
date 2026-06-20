# frozen_string_literal: true

require "time"

module Gem::Skill
  # Core install logic shared by gem_command and bundle_command.
  # Callers are responsible for spinner.auto_spin and title setup before calling.
  module Runner
    # error:        nil on success, message string on failure
    # verify_fixed: true when --verify ran and corrected the skill
    Result = Data.define(:error, :verify_fixed) do
      def ok? = error.nil?

      def self.failure(message) = new(error: message, verify_fixed: false)
      def self.success(verify_fixed: false) = new(error: nil, verify_fixed: verify_fixed)
    end

    # Generate + cache + link one skill, optionally verifying it against source.
    # Returns a Runner::Result.
    def self.install_skill(gem_name, version, spinner, force:, model:, verify: false)
      if Cache.cached?(gem_name, version) && !force
        Linker.link(gem_name, version)
        content = Cache.read(gem_name, version)
        return finalize(gem_name, version, content, spinner, model: model, verify: verify, status: "already cached")
      end

      content = Generator.new(gem_name, version, model: model).generate(force: force)
      Linker.link(gem_name, version)
      finalize(gem_name, version, content, spinner, model: model, verify: verify, status: "done")
    rescue => e
      spinner.error("failed")
      Result.failure(e.message)
    end

    # Run the optional verify pass and settle the spinner + metadata.
    def self.finalize(gem_name, version, content, spinner, model:, verify:, status:)
      unless verify
        spinner.success(status)
        return Result.success
      end

      result = Verifier.new(gem_name, version, model: model).verify(content)

      unless result.verifiable
        Cache.merge_metadata(gem_name, version, verification: {
          verified:       false,
          verified_at:    Time.now.iso8601,
          model:          model,
          skipped_reason: "no installed source available"
        })
        spinner.success("#{status} (no source to verify)")
        return Result.success
      end

      Cache.write_skill(gem_name, version, result.content) if result.changed?
      Cache.merge_metadata(gem_name, version, verification: verification_metadata(result))

      if result.changed?
        spinner.success("verified — fixed")
        Result.success(verify_fixed: true)
      else
        spinner.success("verified — ok")
        Result.success
      end
    rescue => e
      spinner.error("verify failed")
      Result.failure(e.message)
    end
    private_class_method :finalize

    # Records that the skill was verified against real source and whether that
    # verification changed anything. Intentionally minimal — the itemized list of
    # what changed is not retained.
    def self.verification_metadata(result)
      {
        verified:    true,
        verified_at: Time.now.iso8601,
        model:       result.model,
        fixed:       result.changed?
      }
    end
    private_class_method :verification_metadata
  end
end
