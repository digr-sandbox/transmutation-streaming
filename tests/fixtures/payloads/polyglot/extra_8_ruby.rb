# typed: strict
# frozen_string_literal: true

require "autobump_constants"
require "cache_store"
require "did_you_mean"
require "keg_only_reason"
require "lock_file"
require "formula_pin"
require "hardware"
require "utils"
require "utils/bottles"
require "utils/gzip"
require "utils/inreplace"
require "utils/shebang"
require "utils/shell"
require "utils/shell_completion"
require "utils/git_repository"
require "build_environment"
require "build_options"
require "formulary"
require "software_spec"
require "bottle"
require "pour_bottle_check"
require "head_software_spec"
require "bottle_specification"
require "livecheck"
require "service"
require "install_renamed"
require "pkg_version"
require "keg"
require "migrator"
require "linkage_checker"
require "extend/ENV"
require "language/java"
require "language/php"
require "language/python"
require "tab"
require "mktemp"
require "find"
require "utils/spdx"
require "on_system"
require "api"
require "api_hashable"
require "utils/output"
require "pypi_packages"
require "time"

# A formula provides instructions and metadata for Homebrew to install a piece
# of software. Every Homebrew formula is a {Formula}.
# All subclasses of {Formula} (and all Ruby classes) have to be named
# `UpperCase` and `not-use-dashes`.
# A formula specified in `this-formula.rb` should have a class named
# `ThisFormula`. Homebrew does enforce that the name of the file and the class
# correspond.
# Make sure you check with `brew search` that the name is free!
# @abstract
# @see SharedEnvExtension
# @see Pathname
# @see https://www.rubydoc.info/stdlib/fileutils FileUtils
# @see https://docs.brew.sh/Formula-Cookbook Formula Cookbook
# @see https://rubystyle.guide Ruby Style Guide
#
# ### Example
#
# ```ruby
# class Wget < Formula
#   homepage "https://www.gnu.org/software/wget/"
#   url "https://ftp.gnu.org/gnu/wget/wget-1.15.tar.gz"
#   sha256 "52126be8cf1bddd7536886e74c053ad7d0ed2aa89b4b630f76785bac21695fcd"
#
#   def install
#     system "./configure", "--prefix=#{prefix}"
#     system "make", "install"
#   end
# end
# ```
class Formula
  include FileUtils
  include Utils::Shebang
  include Utils::Shell
  include Utils::Output::Mixin
  include Context
  include OnSystem::MacOSAndLinux
  include Homebrew::Livecheck::Constants
  extend Forwardable
  extend Cachable
  extend APIHashable
  extend T::Helpers
  extend Utils::Output::Mixin

  abstract!

  # Used to track formulae that cannot be installed at the same time.
  FormulaConflict = Struct.new(:name, :reason)

  SUPPORTED_NETWORK_ACCESS_PHASES = [:build, :test, :postinstall].freeze
  private_constant :SUPPORTED_NETWORK_ACCESS_PHASES
  DEFAULT_NETWORK_ACCESS_ALLOWED = true
  private_constant :DEFAULT_NETWORK_ACCESS_ALLOWED

  # The name of this {Formula}.
  # e.g. `this-formula`
  #
  # @api public
  sig { returns(String) }
  attr_reader :name

  # The path to the alias that was used to identify this {Formula}.
  # e.g. `/usr/local/Library/Taps/homebrew/homebrew-core/Aliases/another-name-for-this-formula`
  sig { returns(T.nilable(Pathname)) }
  attr_reader :alias_path

  # The name of the alias that was used to identify this {Formula}.
  # e.g. `another-name-for-this-formula`
  sig { returns(T.nilable(String)) }
  attr_reader :alias_name

  # The fully-qualified name of this {Formula}.
  # For core formulae it's the same as {#name}.
  # e.g. `homebrew/tap-name/this-formula`
  #
  # @api public
  sig { returns(String) }
  attr_reader :full_name

  # The fully-qualified alias referring to this {Formula}.
  # For core formulae it's the same as {#alias_name}.
  # e.g. `homebrew/tap-name/another-name-for-this-formula`
  sig { returns(T.nilable(String)) }
  attr_reader :full_alias_name

  # The full path to this {Formula}.
  # e.g. `/usr/local/Library/Taps/homebrew/homebrew-core/Formula/t/this-formula.rb`
  #
  # @api public
  sig { returns(Pathname) }
  attr_reader :path

  # The {Tap} instance associated with this {Formula}.
  # If it's `nil`, then this formula is loaded from a path or URL.
  #
  # @api internal
  sig { returns(T.nilable(Tap)) }
  attr_reader :tap

  # The stable (and default) {SoftwareSpec} for this {Formula}.
  # This contains all the attributes (e.g. URL, checksum) that apply to the
  # stable version of this formula.
  #
  # @api internal
  sig { returns(T.nilable(SoftwareSpec)) }
  attr_reader :stable

  # The HEAD {SoftwareSpec} for this {Formula}.
  # Installed when using `brew install --HEAD`.
  # This is always installed with the version `HEAD` and taken from the latest
  # commit in the version control system.
  # `nil` if there is no HEAD version.
  #
  # @see #stable
  sig { returns(T.nilable(SoftwareSpec)) }
  attr_reader :head

  # The currently active {SoftwareSpec}.
  # @see #determine_active_spec
  sig { returns(SoftwareSpec) }
  attr_reader :active_spec

  protected :active_spec

  # A symbol to indicate currently active {SoftwareSpec}.
  # It's either `:stable` or `:head`.
  # @see #active_spec
  sig { returns(Symbol) }
  attr_reader :active_spec_sym

  # The most recent modified time for source files.
  sig { returns(T.nilable(Time)) }
  attr_reader :source_modified_time

  # Used for creating new Homebrew versions of software without new upstream
  # versions.
  # @see .revision=
  sig { returns(Integer) }
  attr_reader :revision

  # Used to change version schemes for packages.
  # @see .version_scheme=
  sig { returns(Integer) }
  attr_reader :version_scheme

  # Used to indicate API/ABI compatibility for dependencies.
  # @see .compatibility_version=
  sig { returns(T.nilable(Integer)) }
  attr_reader :compatibility_version

  # The current working directory during builds.
  # Will only be non-`nil` inside {#install}.
  sig { returns(T.nilable(Pathname)) }
  attr_reader :buildpath

  # The current working directory during tests.
  # Will only be non-`nil` inside {.test}.
  sig { returns(T.nilable(Pathname)) }
  attr_reader :testpath

  # When installing a bottle (binary package) from a local path this will be
  # set to the full path to the bottle tarball. If not, it will be `nil`.
  sig { returns(T.nilable(Pathname)) }
  attr_accessor :local_bottle_path

  # When performing a build, test, or other loggable action, indicates which
  # log file location to use.
  sig { returns(T.nilable(String)) }
  attr_reader :active_log_type

  # The {BuildOptions} or {Tab} for this {Formula}. Lists the arguments passed
  # and any {.option}s in the {Formula}. Note that these may differ at
  # different times during the installation of a {Formula}. This is annoying
  # but is the result of state that we're trying to eliminate.
  sig { returns(T.any(BuildOptions, Tab)) }
  attr_reader :build

  # Information about PyPI mappings for this {Formula} is stored
  # as {PypiPackages} object.
  sig { returns(PypiPackages) }
  attr_reader :pypi_packages_info

  # Whether this formula should be considered outdated
  # if the target of the alias it was installed with has since changed.
  # Defaults to true.
  sig { returns(T::Boolean) }
  attr_accessor :follow_installed_alias

  alias follow_installed_alias? follow_installed_alias

  # Whether or not to force the use of a bottle.
  sig { returns(T::Boolean) }
  attr_accessor :force_bottle

  sig {
    params(name: String, path: Pathname, spec: Symbol, alias_path: T.nilable(Pathname),
           tap: T.nilable(Tap), force_bottle: T::Boolean).void
  }
  def initialize(name, path, spec, alias_path: nil, tap: nil, force_bottle: false)
    # Only allow instances of subclasses. The base class does not hold any spec information (URLs etc).
    raise "Do not call `Formula.new' directly without a subclass." unless self.class < Formula

    # Stop any subsequent modification of a formula's definition.
    # Changes do not propagate to existing instances of formulae.
    # Now that we have an instance, it's too late to make any changes to the class-level definition.
    self.class.freeze

    @name = name
    @unresolved_path = path
    @path = T.let(path.resolved_path, Pathname)
    @alias_path = alias_path
    @alias_name = T.let((File.basename(alias_path) if alias_path), T.nilable(String))
    @revision = T.let(self.class.revision || 0, Integer)
    @version_scheme = T.let(self.class.version_scheme || 0, Integer)
    @compatibility_version = T.let(self.class.compatibility_version, T.nilable(Integer))
    @head = T.let(nil, T.nilable(SoftwareSpec))
    @stable = T.let(nil, T.nilable(SoftwareSpec))

    @autobump = T.let(true, T::Boolean)
    @no_autobump_message = T.let(nil, T.nilable(T.any(String, Symbol)))

    @force_bottle = force_bottle

    @tap = T.let(tap, T.nilable(Tap))
    @tap ||= if path == Formulary.core_path(name)
      CoreTap.instance
    else
      Tap.from_path(path)
    end

    @pypi_packages_info = T.let(self.class.pypi_packages_info || PypiPackages.new, PypiPackages)

    @full_name = T.let(T.must(full_name_with_optional_tap(name)), String)
    @full_alias_name = T.let(full_name_with_optional_tap(@alias_name), T.nilable(String))

    self.class.spec_syms.each do |sym|
      spec_eval sym
    end

    @active_spec = T.let(determine_active_spec(spec), SoftwareSpec)
    @active_spec_sym = T.let(head? ? :head : :stable, Symbol)
    validate_attributes!
    @build = T.let(active_spec.build, T.any(BuildOptions, Tab))
    @pin = T.let(FormulaPin.new(self), FormulaPin)
    @follow_installed_alias = T.let(true, T::Boolean)
    @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
    @oldname_locks = T.let([], T::Array[FormulaLock])
    @on_system_blocks_exist = T.let(false, T::Boolean)
    @fully_loaded_formula = T.let(nil, T.nilable(Formula))
  end

  sig { params(spec_sym: Symbol).void }
  def active_spec=(spec_sym)
    spec = send(spec_sym)
    raise FormulaSpecificationError, "#{spec_sym} spec is not available for #{full_name}" unless spec

    old_spec_sym = @active_spec_sym
    @active_spec = spec
    @active_spec_sym = spec_sym
    validate_attributes!
    @build = active_spec.build

    return if spec_sym == old_spec_sym

    Dependency.clear_cache
    Requirement.clear_cache
  end

  sig { params(build_options: T.any(BuildOptions, Tab)).void }
  def build=(build_options)
    old_options = @build
    @build = build_options

    return if old_options.used_options == build_options.used_options &&
              old_options.unused_options == build_options.unused_options

    Dependency.clear_cache
    Requirement.clear_cache
  end

  # Ensure the given formula is installed.
  # This is useful for installing a utility formula (e.g. `shellcheck` for `brew style`).
  sig {
    params(
      reason:           String,
      latest:           T::Boolean,
      output_to_stderr: T::Boolean,
      quiet:            T::Boolean,
    ).returns(T.self_type)
  }
  def ensure_installed!(reason: "", latest: false, output_to_stderr: true, quiet: false)
    if output_to_stderr || quiet
      file = if quiet
        File::NULL
      else
        $stderr
      end
      # Call this method itself with redirected stdout
      redirect_stdout(file) do
        return ensure_installed!(latest:, reason:, output_to_stderr: false)
      end
    end

    reason = " for #{reason}" if reason.present?

    unless any_version_installed?
      ohai "Installing `#{name}`#{reason}..."
      safe_system HOMEBREW_BREW_FILE, "install", "--formula", full_name
    end

    if latest && !latest_version_installed?
      ohai "Upgrading `#{name}`#{reason}..."
      safe_system HOMEBREW_BREW_FILE, "upgrade", "--formula", full_name
    end

    self
  end

  sig { returns(T::Boolean) }
  def preserve_rpath? = self.class.preserve_rpath?

  private

  # Allow full name logic to be re-used between names, aliases and installed aliases.
  sig { params(name: T.nilable(String)).returns(T.nilable(String)) }
  def full_name_with_optional_tap(name)
    if name.nil? || @tap.nil? || @tap.core_tap?
      name
    else
      "#{@tap}/#{name}"
    end
  end

  sig { params(name: T.any(String, Symbol)).void }
  def spec_eval(name)
    spec = self.class.send(name).dup
    return unless spec.url

    spec.owner = self
    add_global_deps_to_spec(spec)
    instance_variable_set(:"@#{name}", spec)
  end

  sig { params(spec: SoftwareSpec).void }
  def add_global_deps_to_spec(spec); end

  sig { params(requested: T.any(String, Symbol)).returns(SoftwareSpec) }
  def determine_active_spec(requested)
    spec = send(requested) || stable || head
    spec || raise(FormulaSpecificationError, "#{full_name}: formula requires at least a URL")
  end

  sig { void }
  def validate_attributes!
    if name.blank? || name.match?(/\s/) || !Utils.safe_filename?(name)
      raise FormulaValidationError.new(full_name, :name, name)
    end

    url = active_spec.url
    raise FormulaValidationError.new(full_name, :url, url) if url.blank? || url.match?(/\s/)

    val = version.respond_to?(:to_str) ? version.to_str : version
    return if val.present? && !val.match?(/\s/) && Utils.safe_filename?(val)

    raise FormulaValidationError.new(full_name, :version, val)
  end

  public

  # The alias path that was used to install this formula, if it exists.
  # Can differ from {#alias_path}, which is the alias used to find the formula,
  # and is specified to this instance.
  sig { returns(T.nilable(Pathname)) }
  def installed_alias_path
    build_tab = build
    path = build_tab.source["path"] if build_tab.is_a?(Tab)

    return unless path&.match?(%r{#{HOMEBREW_TAP_DIR_REGEX}/Aliases}o)

    path = Pathname(path)
    return unless path.symlink?

    path
  end

  sig { returns(T.nilable(String)) }
  def installed_alias_name = installed_alias_path&.basename&.to_s

  sig { returns(T.nilable(String)) }
  def full_installed_alias_name = full_name_with_optional_tap(installed_alias_name)

  sig { returns(Pathname) }
  def tap_path
    return path unless (t = tap)
    return Formulary.core_path(name) if t.core_tap?
    return path unless t.installed?

    t.formula_files_by_name[name] || path
  end

  # The path that was specified to find this formula.
  sig { returns(T.nilable(Pathname)) }
  def specified_path
    return Homebrew::API::Internal.cached_formula_json_file_path if loaded_from_internal_api?
    return Homebrew::API::Formula.cached_json_file_path if loaded_from_api?
    return alias_path if alias_path&.exist?

    return @unresolved_path if @unresolved_path.exist?

    return local_bottle_path if local_bottle_path.presence&.exist?

    alias_path || @unresolved_path
  end

  # The name specified to find this formula.
  sig { returns(String) }
  def specified_name
    alias_name || name
  end

  # The name (including tap) specified to find this formula.
  sig { returns(String) }
  def full_specified_name
    full_alias_name || full_name
  end

  # The name specified to install this formula.
  sig { returns(String) }
  def installed_specified_name
    installed_alias_name || name
  end

  # The name (including tap) specified to install this formula.
  sig { returns(String) }
  def full_installed_specified_name
    full_installed_alias_name || full_name
  end

  # Is the currently active {SoftwareSpec} a {#stable} build?
  sig { returns(T::Boolean) }
  def stable?
    active_spec == stable
  end

  # Is the currently active {SoftwareSpec} a {#head} build?
  sig { returns(T::Boolean) }
  def head?
    active_spec == head
  end

  # Is this formula HEAD-only?
  sig { returns(T::Boolean) }
  def head_only?
    !!head && !stable
  end

  # Stop RuboCop from erroneously indenting hash target
  delegate [ # rubocop:disable Layout/HashAlignment
    :bottle_defined?,
    :bottle_tag?,
    :bottled?,
    :bottle_specification,
    :downloader,
  ] => :active_spec

  # The {Bottle} object for the currently active {SoftwareSpec}.
  sig { returns(T.nilable(Bottle)) }
  def bottle
    @bottle ||= T.let(Bottle.new(self, bottle_specification), T.nilable(Bottle)) if bottled?
  end

  # The {Bottle} object for given tag.
  sig { params(tag: T.nilable(Utils::Bottles::Tag)).returns(T.nilable(Bottle)) }
  def bottle_for_tag(tag = nil)
    Bottle.new(self, bottle_specification, tag) if bottled?(tag)
  end

  # The description of the software.
  # @!method desc
  # @see .desc
  delegate desc: :"self.class"

  # The SPDX ID of the software license.
  # @!method license
  # @see .license
  delegate license: :"self.class"

  # The homepage for the software.
  # @!method homepage
  # @see .homepage
  delegate homepage: :"self.class"

  # The `livecheck` specification for the software.
  # @!method livecheck
  # @see .livecheck
  delegate livecheck: :"self.class"

  # Is a `livecheck` specification defined for the software?
  # @!method livecheck_defined?
  # @see .livecheck_defined?
  delegate livecheck_defined?: :"self.class"

  # This is a legacy alias for `#livecheck_defined?`.
  # @!method livecheckable?
  # @see .livecheckable?
  delegate livecheckable?: :"self.class"

  # Exclude the formula from the autobump list.
  # @!method no_autobump!
  # @see .no_autobump!
  delegate no_autobump!: :"self.class"

  # Is the formula in the autobump list?
  # @!method autobump?
  # @see .autobump?
  delegate autobump?: :"self.class"

  # Is a `no_autobump!` method defined?
  # @!method no_autobump_defined?
  # @see .no_autobump_defined?
  delegate no_autobump_defined?: :"self.class"

  delegate no_autobump_message: :"self.class"

  # Is a service specification defined for the software?
  # @!method service?
  # @see .service?
  delegate service?: :"self.class"

  # The version for the currently active {SoftwareSpec}.
  # The version is autodetected from the URL and/or tag so only needs to be
  # declared if it cannot be autodetected correctly.
  # @!method version
  # @see .version
  delegate version: :active_spec

  # Stop RuboCop from erroneously indenting hash target
  delegate [ # rubocop:disable Layout/HashAlignment
    :allow_network_access!,
    :deny_network_access!,
    :network_access_allowed?,
  ] => :"self.class"

  # Whether this formula was loaded using the formulae.brew.sh API.
  # @!method loaded_from_api?
  # @see .loaded_from_api?
  delegate loaded_from_api?: :"self.class"

  # Whether this formula was loaded using the internal formulae.brew.sh API.
  # @!method loaded_from_internal_api?
  # @see .loaded_from_internal_api?
  delegate loaded_from_internal_api?: :"self.class"

  # The API source data used to load this formula.
  # Returns `nil` if the formula was not loaded from the API.
  # @!method api_source
  # @see .api_source
  delegate api_source: :"self.class"

  sig { void }
  def update_head_version
    return unless head?

    head_spec = T.must(head)
    return unless head_spec.downloader.is_a?(VCSDownloadStrategy)
    return unless head_spec.downloader.cached_location.exist?

    path = if ENV["HOMEBREW_ENV"]
      ENV.fetch("PATH")
    else
      PATH.new(ORIGINAL_PATHS)
    end

    with_env(PATH: path) do
      head_spec.version.update_commit(head_spec.downloader.last_commit)
    end
  end

  # The {PkgVersion} for this formula with {version} and {#revision} information.
  sig { returns(PkgVersion) }
  def pkg_version = PkgVersion.new(version, revision)

  # If this is a `@`-versioned formula.
  sig { returns(T::Boolean) }
  def versioned_formula? = name.include?("@")

  # Returns any other `@`-versioned formulae names for any Formula (including versioned formulae).
  sig { returns(T::Array[String]) }
  def versioned_formulae_names
    name_prefix = unversioned_formula_name || name

    versioned_names = if (formula_tap = tap)
      formula_tap.prefix_to_versioned_formulae_names.fetch(name_prefix, [])
    else
      versioned_formula_glob = if name_prefix.end_with?("-full")
        "#{name_prefix.delete_suffix("-full")}@*-full.rb"
      else
        "#{name_prefix}@*.rb"
      end

      formula_names_for_glob(versioned_formula_glob)
    end

    versioned_names.reject do |versioned_name|
      versioned_name == name
    end
  end

  # Returns any `@`-versioned Formula objects for any Formula (including versioned formulae).
  sig { returns(T::Array[Formula]) }
  def versioned_formulae
    versioned_formulae_names.filter_map do |name|
      Formula[name]
    rescue FormulaUnavailableError
      nil
    end.sort_by(&:version).reverse
  end

  sig { returns(T.nilable(String)) }
  def unversioned_formula_name
    return unless versioned_formula?

    name.sub(/@[\d.]+(?=-full$|$)/, "")
  end

  sig { params(glob: String).returns(T::Array[String]) }
  def formula_names_for_glob(glob)
    @formula_names_for_glob ||= T.let({}, T.nilable(T::Hash[String, T::Array[String]]))
    @formula_names_for_glob[glob] ||= if (formula_tap = tap)
      formula_name = File.basename(glob, ".rb")
      if formula_tap.formula_files_by_name.key?(formula_name)
        [formula_name]
      else
        []
      end
    elsif path.exist?
      Pathname.glob((path.dirname/glob).to_s)
              .map { |path| path.basename(".rb").to_s }
              .sort
    else
      raise "Either tap or path is required to list sibling formulae"
    end
  end
  private :formula_names_for_glob

  # Returns the sibling `-full` or non-`-full` formula names for any Formula.
  sig { returns(T::Array[String]) }
  def full_formulae_names
    sibling_name = if name.end_with?("-full")
      name.delete_suffix("-full")
    else
      "#{name}-full"
    end

    formula_names_for_glob("#{sibling_name}.rb")
  end

  # Returns sibling `-full` or non-`-full` Formula objects for any Formula.
  sig { returns(T::Array[Formula]) }
  def full_formulae
    full_formulae_names.filter_map do |formula_name|
      Formula[formula_name]
    rescue FormulaUnavailableError
      nil
    end.sort_by(&:version).reverse
  end

  sig { returns(T.nilable(String)) }
  def link_overwrite_reason
    installed_overwrite_formulae = link_overwrite_formulae.select(&:any_version_installed?)
    return if installed_overwrite_formulae.empty?

    reason_formulae = installed_overwrite_formulae.select(&:linked?)
    status = if reason_formulae.empty?
      reason_formulae = installed_overwrite_formulae
      "installed"
    else
      "linked"
    end

    "#{reason_formulae.map(&:full_name).to_sentence} #{reason_formulae.one? ? "is" : "are"} already #{status}"
  end

  sig { returns(T::Array[String]) }
  def link_overwrite_related_formula_names
    [*versioned_formulae_names, *full_formulae_names, unversioned_formula_name].compact
  end

  # Returns sibling Formula names whose prefix links should be replaced when this Formula is linked.
  sig { returns(T::Array[String]) }
  def link_overwrite_formulae_names
    formula_names = T.let(Set.new, T::Set[String])
    pending_formula_names = T.let([name], T::Array[String])

    pending_formula_names.each do |current_name|
      current_formula = begin
        if current_name == name
          self
        else
          Formula[current_name]
        end
      rescue FormulaUnavailableError
        next
      end

      current_formula.link_overwrite_related_formula_names.each do |related_formula_name|
        next if related_formula_name == name
        next unless formula_names.add?(related_formula_name)

        pending_formula_names << related_formula_name
      end
    end

    formula_names.to_a.sort
  end

  # Returns sibling Formulae whose prefix links should be replaced when this Formula is linked.
  sig { returns(T::Array[Formula]) }
  def link_overwrite_formulae
    link_overwrite_formulae_names.filter_map do |formula_name|
      Formula[formula_name]
    rescue FormulaUnavailableError
      nil
    end
  end

  sig { params(path: Pathname).returns(T.nilable(T.any(String, Symbol))) }
  def link_overwrite_keg_name(path)
    # Don't overwrite files not created by Homebrew.
    return if path.stat.uid != HOMEBREW_ORIGINAL_BREW_FILE.stat.uid

    keg = Keg.for(path)
    # This keg doesn't belong to any current core/tap formula, most likely coming from a DIY install.
    return if keg.tab.tap.nil?

    keg.name
  rescue NotAKegError, Errno::ENOENT
    # File doesn't belong to any keg.
    :missing
  end

  sig {
    params(keg_name: T.nilable(T.any(String, Symbol)), overwrite_formulae: T::Array[Formula]).returns(T::Boolean)
  }
  def implied_link_overwrite?(keg_name, overwrite_formulae)
    return false if overwrite_formulae.empty?
    return false if keg_name.nil?

    case keg_name
    when :missing
      # File doesn't belong to any keg, so implied overwrites do not apply.
      false
    else
      overwrite_formulae.any? do |formula|
        formula.possible_names.include?(keg_name)
      end
    end
  end
  # Whether this {Formula} is version-synced with other formulae.
  sig { returns(T::Boolean) }
  def synced_with_other_formulae?
    return false if @tap.nil?

    @tap.synced_versions_formulae.any? { |synced_formulae| synced_formulae.include?(name) }
  end

  # A named {Resource} for the currently active {SoftwareSpec}.
  # Additional downloads can be defined as {#resource}s.
  # {Resource#stage} will create a temporary directory and yield to a block.
  #
  # ### Example
  #
  # ```ruby
  # resource("additional_files").stage { bin.install "my/extra/tool" }
  # ```
  #
  # FIXME: This should not actually take a block. All resources should be defined
  #        at the top-level using {Formula.resource} instead
  #        (see https://github.com/Homebrew/brew/issues/17203#issuecomment-2093654431).
  #
  # @api public
  sig {
    params(name: String, klass: T.class_of(Resource), block: T.nilable(T.proc.bind(Resource).void))
      .returns(T.nilable(Resource))
  }
  def resource(name = T.unsafe(nil), klass = T.unsafe(nil), &block)
    if klass.nil?
      active_spec.resource(*name, &block)
    else
      active_spec.resource(name, klass, &block)
    end
  end

  # Old names for the formula.
  #
  # @api internal
  sig { returns(T::Array[String]) }
  def oldnames
    @oldnames ||= T.let(
      if (tap = self.tap)
        Tap.tap_migration_oldnames(tap, name) + tap.formula_reverse_renames.fetch(name, [])
      else
        []
      end, T.nilable(T::Array[String])
    )
  end

  # All aliases for the formula.
  #
  # @api internal
  sig { returns(T::Array[String]) }
  def aliases
    @aliases ||= T.let(
      if (tap = self.tap)
        tap.alias_reverse_table.fetch(full_name, []).map { it.split("/").fetch(-1) }
      else
        []
      end, T.nilable(T::Array[String])
    )
  end

  # The {Resource}s for the currently active {SoftwareSpec}.
  # @!method resources
  def_delegator :"active_spec.resources", :values, :resources

  # The {Dependency}s for the currently active {SoftwareSpec}.
  #
  # @api internal
  delegate deps: :active_spec

  # The declared {Dependency}s for the currently active {SoftwareSpec} (i.e. including those provided by macOS).
  delegate declared_deps: :active_spec

  # The {Requirement}s for the currently active {SoftwareSpec}.
  delegate requirements: :active_spec

  # The cached download for the currently active {SoftwareSpec}.
  delegate cached_download: :active_spec

  # Deletes the download for the currently active {SoftwareSpec}.
  delegate clear_cache: :active_spec

  # The list of patches for the currently active {SoftwareSpec}.
  def_delegator :active_spec, :patches, :patchlist

  # The options for the currently active {SoftwareSpec}.
  delegate options: :active_spec

  # The deprecated options for the currently active {SoftwareSpec}.
  delegate deprecated_options: :active_spec

  # The deprecated option flags for the currently active {SoftwareSpec}.
  delegate deprecated_flags: :active_spec

  # If a named option is defined for the currently active {SoftwareSpec}.
  # @!method option_defined?
  delegate option_defined?: :active_spec

  # All the {.fails_with} for the currently active {SoftwareSpec}.
  delegate compiler_failures: :active_spec

  # If this {Formula} is installed.
  # This is actually just a check for if the {#latest_installed_prefix} directory
  # exists and is not empty.
  sig { returns(T::Boolean) }
  def latest_version_installed?
    (dir = latest_installed_prefix).directory? && !dir.empty?
  end

  # If at least one version of {Formula} is installed.
  #
  # @api public
  sig { returns(T::Boolean) }
  def any_version_installed?
    installed_prefixes.any? { |keg| (keg/AbstractTab::FILENAME).file? }
  end

  # The link status symlink directory for this {Formula}.
  # You probably want {#opt_prefix} instead.
  #
  # @api internal
  sig { returns(Pathname) }
  def linked_keg
    linked_keg = possible_names.map { |name| HOMEBREW_LINKED_KEGS/name }
                               .find(&:directory?)
    return linked_keg if linked_keg.present?

    HOMEBREW_LINKED_KEGS/name
  end

  sig { returns(T.nilable(PkgVersion)) }
  def latest_head_version
    head_versions = installed_prefixes.filter_map do |pn|
      pn_pkgversion = PkgVersion.parse(pn.basename.to_s)
      pn_pkgversion if pn_pkgversion.head?
    end

    head_versions.max_by do |pn_pkgversion|
      [Keg.new(prefix(pn_pkgversion)).tab.source_modified_time, pn_pkgversion.revision]
    end
  end

  sig { returns(T.nilable(Pathname)) }
  def latest_head_prefix
    head_version = latest_head_version
    prefix(head_version) if head_version
  end

  sig { params(version: PkgVersion, fetch_head: T::Boolean).returns(T::Boolean) }
  def head_version_outdated?(version, fetch_head: false)
    tab = Tab.for_keg(prefix(version))

    return true if tab.version_scheme < version_scheme

    tab_stable_version = tab.stable_version
    return true if stable && tab_stable_version && tab_stable_version < T.must(stable).version
    return false unless fetch_head
    return false unless head&.downloader.is_a?(VCSDownloadStrategy)

    downloader = T.must(head).downloader

    with_context quiet: true do
      downloader.commit_outdated?(version.version.commit)
    end
  end

  sig { params(fetch_head: T::Boolean).returns(PkgVersion) }
  def latest_head_pkg_version(fetch_head: false)
    return pkg_version unless (latest_version = latest_head_version)
    return latest_version unless head_version_outdated?(latest_version, fetch_head:)

    downloader = T.must(head).downloader
    with_context quiet: true do
      PkgVersion.new(Version.new("HEAD-#{downloader.last_commit}"), revision)
    end
  end

  # The latest prefix for this formula. Checks for {#head} and then {#stable}'s {#prefix}.
  sig { returns(Pathname) }
  def latest_installed_prefix
    if head && (head_version = latest_head_version) && !head_version_outdated?(head_version)
      T.must(latest_head_prefix)
    elsif stable && (stable_prefix = prefix(PkgVersion.new(T.must(stable).version, revision))).directory?
      stable_prefix
    else
      prefix
    end
  end

  # The directory in the Cellar that the formula is installed to.
  # This directory points to {#opt_prefix} if it exists and if {#prefix} is not
  # called from within the same formula's {#install} or {#post_install} methods.
  # Otherwise, return the full path to the formula's keg (versioned Cellar path).
  #
  # @api public
  sig { params(version: T.any(String, PkgVersion)).returns(Pathname) }
  def prefix(version = pkg_version)
    versioned_prefix = versioned_prefix(version)
    version = PkgVersion.parse(version) if version.is_a?(String)
    if !@prefix_returns_versioned_prefix && version == pkg_version &&
       versioned_prefix.directory? && Keg.new(versioned_prefix).optlinked?
      opt_prefix
    else
      versioned_prefix
    end
  end

  # Is the formula linked?
  #
  # @api internal
  sig { returns(T::Boolean) }
  def linked? = linked_keg.exist?

  # Is the formula linked to `opt`?
  sig { returns(T::Boolean) }
  def optlinked? = opt_prefix.symlink?

  # If a formula's linked keg points to the prefix.
  sig { params(version: T.any(String, PkgVersion)).returns(T::Boolean) }
  def prefix_linked?(version = pkg_version)
    return false unless linked?

    linked_keg.resolved_path == versioned_prefix(version)
  end

  # {PkgVersion} of the linked keg for the formula.
  sig { returns(T.nilable(PkgVersion)) }
  def linked_version
    return unless linked?

    Keg.for(linked_keg).version
  end

  # The parent of the prefix; the named directory in the Cellar containing all
  # installed versions of this software.
  sig { returns(Pathname) }
  def rack = HOMEBREW_CELLAR/name

  # All currently installed prefix directories.
  sig { returns(T::Array[Pathname]) }
  def installed_prefixes
    possible_names.map { |name| HOMEBREW_CELLAR/name }
                  .select(&:directory?)
                  .flat_map(&:subdirs)
                  .sort_by(&:basename)
  end

  # All currently installed kegs.
  sig { returns(T::Array[Keg]) }
  def installed_kegs
    installed_prefixes.map { |dir| Keg.new(dir) }
  end

  # The directory where the formula's binaries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Examples
  #
  # Need to install into the {.bin} but the makefile doesn't `mkdir -p prefix/bin`?
  #
  # ```ruby
  # bin.mkpath
  # ```
  #
  # No `make install` available?
  #
  # ```ruby
  # bin.install "binary1"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def bin = prefix/"bin"

  # The directory where the formula's documentation should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def doc = share/"doc"/name

  # The directory where the formula's headers should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # include.install "example.h"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def include = prefix/"include"

  # The directory where the formula's info files should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def info = share/"info"

  # The directory where the formula's libraries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # lib.install "example.dylib"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def lib = prefix/"lib"

  # The directory where the formula's binaries should be installed.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  # It is commonly used to install files that we do not wish to be
  # symlinked into `HOMEBREW_PREFIX` from one of the other directories and
  # instead manually create symlinks or wrapper scripts into e.g. {#bin}.
  #
  # ### Example
  #
  # ```ruby
  # libexec.install "foo.jar"
  # bin.write_jar_script libexec/"foo.jar", "foo"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def libexec = prefix/"libexec"

  # The root directory where the formula's manual pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # Often one of the more specific `man` functions should be used instead,
  # e.g. {#man1}.
  #
  # @api public
  sig { returns(Pathname) }
  def man = share/"man"

  # The directory where the formula's man1 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # man1.install "example.1"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def man1 = man/"man1"

  # The directory where the formula's man2 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man2 = man/"man2"

  # The directory where the formula's man3 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # man3.install "man.3"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def man3 = man/"man3"

  # The directory where the formula's man4 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man4 = man/"man4"

  # The directory where the formula's man5 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man5 = man/"man5"

  # The directory where the formula's man6 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man6 = man/"man6"

  # The directory where the formula's man7 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man7 = man/"man7"

  # The directory where the formula's man8 pages should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def man8 = man/"man8"

  # The directory where the formula's `sbin` binaries should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # Generally we try to migrate these to {#bin} instead.
  #
  # @api public
  sig { returns(Pathname) }
  def sbin = prefix/"sbin"

  # The directory where the formula's shared files should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Examples
  #
  # Need a custom directory?
  #
  # ```ruby
  # (share/"concept").mkpath
  # ```
  #
  # Installing something into another custom directory?
  #
  # ```ruby
  # (share/"concept2").install "ducks.txt"
  # ```
  #
  # Install `./example_code/simple/ones` to `share/demos`:
  #
  # ```ruby
  # (share/"demos").install "example_code/simple/ones"
  # ```
  #
  # Install `./example_code/simple/ones` to `share/demos/examples`:
  #
  # ```ruby
  # (share/"demos").install "example_code/simple/ones" => "examples"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def share = prefix/"share"

  # The directory where the formula's shared files should be installed,
  # with the name of the formula appended to avoid linking conflicts.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # ### Example
  #
  # No `make install` available?
  #
  # ```ruby
  # pkgshare.install "examples"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def pkgshare = prefix/"share"/name

  # The directory where Emacs Lisp files should be installed, with the
  # formula name appended to avoid linking conflicts.
  #
  # ### Example
  #
  # To install an Emacs mode included with a software package:
  #
  # ```ruby
  # elisp.install "contrib/emacs/example-mode.el"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def elisp = prefix/"share/emacs/site-lisp"/name

  # The directory where the formula's Frameworks should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  #
  # @api public
  sig { returns(Pathname) }
  def frameworks = prefix/"Frameworks"

  # The directory where the formula's kernel extensions should be installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  # This is not symlinked into `HOMEBREW_PREFIX`.
  #
  # @api public
  sig { returns(Pathname) }
  def kext_prefix = prefix/"Library/Extensions"

  # The directory where the formula's configuration files should be installed.
  # Anything using `etc.install` will not overwrite other files on e.g. upgrades
  # but will write a new file named `*.default`.
  # This directory is not inside the `HOMEBREW_CELLAR` so it persists
  # across upgrades.
  #
  # @api public
  sig { returns(Pathname) }
  def etc = (HOMEBREW_PREFIX/"etc").extend(InstallRenamed)

  # A subdirectory of `etc` with the formula name suffixed,
  # e.g. `$HOMEBREW_PREFIX/etc/openssl@1.1`.
  # Anything using `pkgetc.install` will not overwrite other files on
  # e.g. upgrades but will write a new file named `*.default`.
  #
  # @api public
  sig { returns(Pathname) }
  def pkgetc = (HOMEBREW_PREFIX/"etc"/name).extend(InstallRenamed)

  # The directory where the formula's variable files should be installed.
  # This directory is not inside the `HOMEBREW_CELLAR` so it persists
  # across upgrades.
  #
  # @api public
  sig { returns(Pathname) }
  def var = HOMEBREW_PREFIX/"var"

  # The directory where the formula's `zsh` function files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def zsh_function = share/"zsh/site-functions"

  # The directory where the formula's `fish` function files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def fish_function = share/"fish/vendor_functions.d"

  # The directory where the formula's `bash` completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def bash_completion = prefix/"etc/bash_completion.d"

  # The directory where the formula's `zsh` completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def zsh_completion = share/"zsh/site-functions"

  # The directory where the formula's `fish` completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def fish_completion = share/"fish/vendor_completions.d"

  # The directory where the formula's PowerShell completion files should be
  # installed.
  # This is symlinked into `HOMEBREW_PREFIX` after installation or with
  # `brew link` for formulae that are not keg-only.
  #
  # @api public
  sig { returns(Pathname) }
  def pwsh_completion = share/"pwsh/completions"

  # The directory used for as the prefix for {#etc} and {#var} files on
  # installation so, despite not being in `HOMEBREW_CELLAR`, they are installed
  # there after pouring a bottle.
  sig { returns(Pathname) }
  def bottle_prefix = prefix/".bottle"

  # The directory where the formula's installation or test logs will be written.
  sig { returns(Pathname) }
  def logs = HOMEBREW_LOGS + name

  # The prefix, if any, to use in filenames for logging current activity.
  sig { returns(String) }
  def active_log_prefix
    if active_log_type
      "#{active_log_type}."
    else
      ""
    end
  end

  # Runs a block with the given log type in effect for its duration.
  sig {
    type_parameters(:U).params(
      log_type: String,
      _block:   T.proc.returns(T.type_parameter(:U)),
    ).returns(T.type_parameter(:U))
  }
  def with_logging(log_type, &_block)
    old_log_type = @active_log_type
    @active_log_type = T.let(log_type, T.nilable(String))
    yield
  ensure
    @active_log_type = old_log_type
  end

  # The generated launchd {.plist} service name.
  sig { returns(String) }
  def plist_name = service.plist_name

  # The generated service name.
  sig { returns(String) }
  def service_name = service.service_name

  # The generated launchd {.service} file path.
  sig { returns(Pathname) }
  def launchd_service_path = (any_installed_prefix || opt_prefix)/"#{plist_name}.plist"

  # The generated systemd {.service} file path.
  sig { returns(Pathname) }
  def systemd_service_path = (any_installed_prefix || opt_prefix)/"#{service_name}.service"

  # The generated systemd {.timer} file path.
  sig { returns(Pathname) }
  def systemd_timer_path = (any_installed_prefix || opt_prefix)/"#{service_name}.timer"

  # The service specification for the software.
  sig { returns(Homebrew::Service) }
  def service
    @service ||= T.let(Homebrew::Service.new(self, &self.class.service), T.nilable(Homebrew::Service))
  end

  # A stable path for this formula, when installed. Contains the formula name
  # but no version number. Only the active version will be linked here if
  # multiple versions are installed.
  #
  # This is the preferred way to refer to a formula in plists or from another
  # formula, as the path is stable even when the software is updated.
  #
  # ### Example
  #
  # ```ruby
  # args << "--with-readline=#{Formula["readline"].opt_prefix}" if build.with? "readline"
  # ```
  #
  # @api public
  sig { returns(Pathname) }
  def opt_prefix = HOMEBREW_PREFIX/"opt"/name

  # Same as {#bin}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_bin = opt_prefix/"bin"

  # Same as {#include}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_include = opt_prefix/"include"

  # Same as {#lib}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_lib = opt_prefix/"lib"

  # Same as {#libexec}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_libexec = opt_prefix/"libexec"

  # Same as {#sbin}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_sbin = opt_prefix/"sbin"

  # Same as {#share}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_share = opt_prefix/"share"

  # Same as {#pkgshare}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_pkgshare = opt_prefix/"share"/name

  # Same as {#elisp}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_elisp = opt_prefix/"share/emacs/site-lisp"/name

  # Same as {#frameworks}, but relative to {#opt_prefix} instead of {#prefix}.
  #
  # @api public
  sig { returns(Pathname) }
  def opt_frameworks = opt_prefix/"Frameworks"

  # Indicates that this formula supports bottles. (Not necessarily that one
  # should be used in the current installation run.)
  # Can be overridden to selectively disable bottles from formulae.
  # Defaults to true so overridden version does not have to check if bottles
  # are supported.
  # Replaced by {.pour_bottle?}'s `satisfy` method if it is specified.
  sig { returns(T::Boolean) }
  def pour_bottle? = true

  delegate pour_bottle_check_unsatisfied_reason: :"self.class"

  # Can be overridden to run commands on both source and bottle installation.
  sig { overridable.void }
  def post_install; end

  sig { returns(T::Boolean) }
  def post_install_defined?
    method(:post_install).owner != Formula
  end

  sig { void }
  def install_etc_var
    etc_var_dirs = [bottle_prefix/"etc", bottle_prefix/"var"]
    Find.find(*etc_var_dirs.select(&:directory?)) do |path|
      path = Pathname.new(path)
      path.extend(InstallRenamed)
      path.cp_path_sub(bottle_prefix, HOMEBREW_PREFIX)
      path
    end
  end

  sig { void }
  def run_post_install
    @prefix_returns_versioned_prefix = T.let(true, T.nilable(T::Boolean))
    build = self.build

    begin
      self.build = Tab.for_formula(self)

      new_env = {
        TMPDIR:        HOMEBREW_TEMP,
        TEMP:          HOMEBREW_TEMP,
        TMP:           HOMEBREW_TEMP,
        _JAVA_OPTIONS: "-Djava.io.tmpdir=#{HOMEBREW_TEMP}",
        HOMEBREW_PATH: nil,
        PATH:          PATH.new(ORIGINAL_PATHS),
      }

      with_env(new_env) do
        ENV.clear_sensitive_environment!
        ENV.activate_extensions!

        with_logging("post_install") do
          post_install
        end
      end
    ensure
      self.build = build
      @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
    end
  end

  # Warn the user about any Homebrew-specific issues or quirks for this package.
  # These should not contain setup instructions that would apply to installation
  # through a different package manager on a different OS.
  #
  # ### Example
  #
  # ```ruby
  # def caveats
  #   <<~EOS
  #     Are optional. Something the user must be warned about?
  #   EOS
  # end
  # ```
  #
  # ```ruby
  # def caveats
  #   s = <<~EOS
  #     Print some important notice to the user when `brew info [formula]` is
  #     called or when brewing a formula.
  #     This is optional. You can use all the vars like #{version} here.
  #   EOS
  #   s += "Some issue only on older systems" if MacOS.version < :monterey
  #   s
  # end
  # ```
  sig { overridable.returns(T.nilable(String)) }
  def caveats = nil

  # Rarely, you don't want your library symlinked into the main prefix.
  # See `gettext.rb` for an example.
  # @see .keg_only
  #
  # @api internal
  sig { returns(T::Boolean) }
  def keg_only?
    return false unless keg_only_reason

    keg_only_reason.applicable?
  end

  delegate keg_only_reason: :"self.class"

  # @see .skip_clean
  sig { params(path: Pathname).returns(T::Boolean) }
  def skip_clean?(path)
    return true if path.extname == ".la" && T.must(self.class.skip_clean_paths).include?(:la)

    to_check = path.relative_path_from(prefix).to_s
    T.must(self.class.skip_clean_paths).include? to_check
  end

  # @see .link_overwrite
  # Explicit `link_overwrite` paths may also be implied for related formula families.
  sig { params(path: Pathname).returns(T::Boolean) }
  def link_overwrite?(path)
    # Don't overwrite files that belong to another keg except when that
    # keg's formula is deleted.
    case keg_name = link_overwrite_keg_name(path)
    when String
      begin
        f = Formulary.factory(keg_name)
      rescue FormulaUnavailableError
        # formula for this keg is deleted, so defer to allowlist
      rescue TapFormulaAmbiguityError
        return false # this keg belongs to another formula
      else
        # Ensure `keg_name` maps cleanly to the resolved formula via `possible_names`.
        return false unless f.possible_names.include?(keg_name)
      end
    when :missing
      # File doesn't belong to any keg, so defer to overwrite checks below.
    else
      return false
    end

    to_check = path.relative_path_from(HOMEBREW_PREFIX).to_s
    return true if T.must(self.class.link_overwrite_paths).any? do |p|
      p.to_s == to_check ||
      to_check.start_with?("#{p.to_s.chomp("/")}/") ||
      /^#{Regexp.escape(p.to_s).gsub('\*', ".*?")}$/.match?(to_check)
    end

    implied_link_overwrite?(keg_name, link_overwrite_formulae)
  end

  # Whether this {Formula} is deprecated (i.e. warns on installation).
  # Defaults to false.
  # @!method deprecated?
  # @return [Boolean]
  # @see .deprecate!
  delegate deprecated?: :"self.class"

  # The date that this {Formula} was or becomes deprecated.
  # Returns `nil` if no date is specified.
  # @!method deprecation_date
  # @return Date
  # @see .deprecate!
  delegate deprecation_date: :"self.class"

  # The reason this {Formula} is deprecated.
  # Returns `nil` if no reason is specified or the formula is not deprecated.
  # @!method deprecation_reason
  # @return [String, Symbol]
  # @see .deprecate!
  delegate deprecation_reason: :"self.class"

  # The replacement formula for this deprecated {Formula}.
  # Returns `nil` if no replacement is specified or the formula is not deprecated.
  # @!method deprecation_replacement_formula
  # @return [String]
  # @see .deprecate!
  delegate deprecation_replacement_formula: :"self.class"

  # The replacement cask for this deprecated {Formula}.
  # Returns `nil` if no replacement is specified or the formula is not deprecated.
  # @!method deprecation_replacement_cask
  # @return [String]
  # @see .deprecate!
  delegate deprecation_replacement_cask: :"self.class"

  # The arguments that were used to deprecate this {Formula}.
  # Returns `nil` if `deprecate!` was not called.
  # @!method deprecate_args
  # @return [Hash<Symbol, Object>]
  # @api private
  delegate deprecate_args: :"self.class"

  # Whether this {Formula} is disabled (i.e. cannot be installed).
  # Defaults to false.
  # @!method disabled?
  # @return [Boolean]
  # @see .disable!
  delegate disabled?: :"self.class"

  # The date that this {Formula} was or becomes disabled.
  # Returns `nil` if no date is specified.
  # @!method disable_date
  # @return Date
  # @see .disable!
  delegate disable_date: :"self.class"

  # The reason this {Formula} is disabled.
  # Returns `nil` if no reason is specified or the formula is not disabled.
  # @!method disable_reason
  # @return [String, Symbol]
  # @see .disable!
  delegate disable_reason: :"self.class"

  # The replacement formula for this disabled {Formula}.
  # Returns `nil` if no replacement is specified or the formula is not disabled.
  # @!method disable_replacement_formula
  # @return [String]
  # @see .disable!
  delegate disable_replacement_formula: :"self.class"

  # The replacement cask for this disabled {Formula}.
  # Returns `nil` if no replacement is specified or the formula is not disabled.
  # @!method disable_replacement_cask
  # @return [String]
  # @see .disable!
  delegate disable_replacement_cask: :"self.class"

  # The arguments that were used to disable this {Formula}.
  # Returns `nil` if `disable!` was not called.
  # @!method disable_args
  # @return [Hash<Symbol, Object>]
  # @api private
  delegate disable_args: :"self.class"

  sig { returns(T::Boolean) }
  def skip_cxxstdlib_check?
    odisabled "`Formula#skip_cxxstdlib_check?`"
    false
  end

  sig { void }
  def patch
    return if patchlist.empty?

    ohai "Patching"
    patchlist.each(&:apply)
  end

  sig { params(is_data: T::Boolean).void }
  def selective_patch(is_data: false)
    patches = patchlist.select { |p| p.is_a?(DATAPatch) == is_data }
    return if patches.empty?

    patchtype = if is_data
      "DATA"
    else
      "non-DATA"
    end
    ohai "Applying #{patchtype} patches"
    patches.each(&:apply)
  end

  # Yields `|self,staging|` with current working directory set to the uncompressed tarball
  # where staging is a {Mktemp} staging context.
  sig(:final) {
    params(fetch: T::Boolean, keep_tmp: T::Boolean, debug_symbols: T::Boolean, interactive: T::Boolean,
           _blk: T.proc.params(arg0: Formula, arg1: Mktemp).void).void
  }
  def brew(fetch: true, keep_tmp: false, debug_symbols: false, interactive: false, &_blk)
    @prefix_returns_versioned_prefix = T.let(true, T.nilable(T::Boolean))
    active_spec.fetch if fetch
    stage(interactive:, debug_symbols:) do |staging|
      staging.retain! if keep_tmp || debug_symbols

      prepare_patches
      fetch_patches if fetch

      begin
        yield self, staging
      rescue
        staging.retain! if interactive || debug?
        raise
      ensure
        %w[
          config.log
          CMakeCache.txt
          CMakeConfigureLog.yaml
          meson-log.txt
        ].each do |logfile|
          Dir["**/#{logfile}"].each do |logpath|
            destdir = logs/File.dirname(logpath)
            mkdir_p destdir
            cp logpath, destdir
          end
        end
      end
    end
  ensure
    @prefix_returns_versioned_prefix = T.let(false, T.nilable(T::Boolean))
  end

  sig { returns(T::Array[String]) }
  def lock
    @lock = T.let(FormulaLock.new(name), T.nilable(FormulaLock))
    T.must(@lock).lock

    oldnames.each do |oldname|
      next unless (oldname_rack = HOMEBREW_CELLAR/oldname).exist?
      next if oldname_rack.resolved_path != rack

      oldname_lock = FormulaLock.new(oldname)
      oldname_lock.lock
      @oldname_locks << oldname_lock
    end
  end

  sig { returns(T::Array[FormulaLock]) }
  def unlock
    @lock&.unlock
    @oldname_locks.each(&:unlock)
  end

  sig { returns(T::Array[String]) }
  def oldnames_to_migrate
    oldnames.select do |oldname|
      old_rack = HOMEBREW_CELLAR/oldname
      next false unless old_rack.directory?
      next false if old_rack.subdirs.empty?

      tap == Tab.for_keg(old_rack.subdirs.min).tap
    end
  end

  sig { returns(T::Boolean) }
  def migration_needed?
    !oldnames_to_migrate.empty? && !rack.exist?
  end

  sig { params(fetch_head: T::Boolean).returns(T::Array[Keg]) }
  def outdated_kegs(fetch_head: false)
    raise Migrator::MigrationNeededError.new(oldnames_to_migrate.fetch(0), name) if migration_needed?

    cache_key = "#{full_name}-#{fetch_head}"
    Formula.cache[:outdated_kegs] ||= {}
    Formula.cache[:outdated_kegs][cache_key] ||= begin
      all_kegs = []
      current_version = T.let(false, T::Boolean)
      latest = latest_formula

      installed_kegs.each do |keg|
        all_kegs << keg
        version = keg.version
        next if version.head?

        next if latest.version_scheme > keg.version_scheme && latest.pkg_version != version
        next if latest.version_scheme == keg.version_scheme && latest.pkg_version > version

        # don't consider this keg current if there's a newer formula available
        next if follow_installed_alias? && new_formula_available?

        # this keg is the current version of the formula, but only consider it current
        # if it's actually linked - an unlinked current version means we're outdated
        next if !keg.optlinked? && !keg.linked? && !pinned?

        current_version = true
        break
      end

      if current_version ||
         ((head_version = latest_head_version) && !head_version_outdated?(head_version, fetch_head:))
        []
      else
        all_kegs += old_installed_formulae.flat_map(&:installed_kegs)
        all_kegs.sort_by(&:scheme_and_version)
      end
    end
  end

  sig { returns(T::Boolean) }
  def new_formula_available?
    installed_alias_target_changed? && !latest_formula.latest_version_installed?
  end

  sig { returns(T.nilable(Formula)) }
  def current_installed_alias_target
    Formulary.factory(T.must(full_installed_alias_name)) if installed_alias_path
  end

  # Has the target of the alias used to install this formula changed?
  # Returns false if the formula wasn't installed with an alias.
  sig { returns(T::Boolean) }
  def installed_alias_target_changed?
    target = current_installed_alias_target
    return false unless target

    target.name != name
  end

  # Is this formula the target of an alias used to install an old formula?
  sig { returns(T::Boolean) }
  def supersedes_an_installed_formula? = old_installed_formulae.any?

  # Has the alias used to install the formula changed, or are different
  # formulae already installed with this alias?
  sig { returns(T::Boolean) }
  def alias_changed?
    installed_alias_target_changed? || supersedes_an_installed_formula?
  end

  # If the alias has changed value, return the new formula.
  # Otherwise, return the latest version of the current formula.
  sig { returns(Formula) }
  def latest_formula
    installed_alias_target_changed? ? T.must(current_installed_alias_target) : self
  end

  sig { returns(T::Array[Formula]) }
  def old_installed_formulae
    # If this formula isn't the current target of the alias,
    # it doesn't make sense to say that other formulae are older versions of it
    # because we don't know which came first.
    return [] if alias_path.nil? || installed_alias_target_changed?

    self.class.installed_with_alias_path(alias_path).reject { |f| f.name == name }
  end

  # Check whether the installed formula is outdated.
  #
  # @api internal
  sig { params(fetch_head: T::Boolean).returns(T::Boolean) }
  def outdated?(fetch_head: false)
    !outdated_kegs(fetch_head:).empty?
  rescue Migrator::MigrationNeededError
    true
  end

  def_delegators :@pin, :pinnable?, :pinned_version, :pin, :unpin

  # @!attribute [r] pinned?
  # @api internal
  delegate pinned?: :@pin

  sig { params(other: T.untyped).returns(T::Boolean) }
  def ==(other)
    self.class == other.class &&
      name == other.name &&
      active_spec_sym == other.active_spec_sym
  end
  alias eql? ==

  sig { returns(Integer) }
  def hash = name.hash

  sig { params(other: BasicObject).returns(T.nilable(Integer)) }
  def <=>(other)
    case other
    when Formula then name <=> other.name
    end
  end

  sig { returns(T::Array[String]) }
  def possible_names
    [name, *oldnames, *aliases].compact
  end

  # @api public
  sig { returns(String) }
  def to_s = name

  sig { returns(String) }
  def inspect
    "#<Formula #{name} (#{active_spec_sym}) #{path}>"
  end

  # Standard parameters for Cabal-v2 builds.
  #
  # @api public
  sig { returns(T::Array[String]) }
  def std_cabal_v2_args
    # cabal-install's dependency-resolution backtracking strategy can
    # easily need more than the default 2,000 maximum number of
    # "backjumps," since Hackage is a fast-moving, rolling-release
    # target. The highest known needed value by a formula was 43,478
    # for git-annex, so 100,000 should be enough to avoid most
    # gratuitous backjumps build failures.
    ["--jobs=#{ENV.make_jobs}", "--max-backjumps=100000", "--install-method=copy", "--installdir=#{bin}"]
  end

  # Standard parameters for Cargo builds.
  #
  # @api public
  sig {
    params(
      root:     T.any(String, Pathname),
      path:     T.any(String, Pathname),
      features: T.nilable(T.any(String, T::Array[String])),
    ).returns(T::Array[String])
  }
  def std_cargo_args(root: prefix, path: ".", features: nil)
    args = ["--jobs", ENV.make_jobs.to_s, "--locked", "--root=#{root}", "--path=#{path}"]
    args += ["--features=#{Array(features).join(",")}"] if features
    args
  end

  # Standard parameters for CMake builds.
  #
  # Setting `CMAKE_FIND_FRAMEWORK` to "LAST" tells CMake to search for our
  # libraries before trying to utilize Frameworks, many of which will be from
  # 3rd party installs.
  #
  # @api public
  sig {
    params(
      install_prefix: T.any(String, Pathname),
      install_libdir: T.any(String, Pathname),
      find_framework: String,
    ).returns(T::Array[String])
  }
  def std_cmake_args(install_prefix: prefix, install_libdir: "lib", find_framework: "LAST")
    %W[
      -DCMAKE_INSTALL_PREFIX=#{install_prefix}
      -DCMAKE_INSTALL_LIBDIR=#{install_libdir}
      -DCMAKE_BUILD_TYPE=Release
      -DCMAKE_FIND_FRAMEWORK=#{find_framework}
      -DCMAKE_VERBOSE_MAKEFILE=ON
      -DCMAKE_PROJECT_TOP_LEVEL_INCLUDES=#{HOMEBREW_LIBRARY_PATH}/cmake/trap_fetchcontent_provider.cmake
      -Wno-dev
      -DBUILD_TESTING=OFF
    ]
  end

  # Standard parameters for configure builds.
  #
  # @api public
  sig {
    params(
      prefix: T.any(String, Pathname),
      libdir: T.any(String, Pathname),
    ).returns(T::Array[String])
  }
  def std_configure_args(prefix: self.prefix, libdir: "lib")
    libdir = Pathname(libdir).expand_path(prefix)
    ["--disable-debug", "--disable-dependency-tracking", "--prefix=#{prefix}", "--libdir=#{libdir}"]
  end

  # Standard parameters for Go builds.
  #
  # @api public
  sig {
    params(
      output:  T.any(String, Pathname),
      ldflags: T.nilable(T.any(String, T::Array[String])),
      gcflags: T.nilable(T.any(String, T::Array[String])),
      tags:    T.nilable(T.any(String, T::Array[String])),
    ).returns(T::Array[String])
  }
  def std_go_args(output: bin/name, ldflags: nil, gcflags: nil, tags: nil)
    args = ["-trimpath", "-o=#{output}"]
    args += ["-tags=#{Array(tags).join(" ")}"] if tags
    args += ["-ldflags=#{Array(ldflags).join(" ")}"] if ldflags
    args += ["-gcflags=#{Array(gcflags).join(" ")}"] if gcflags
    args
  end

  # Standard parameters for Meson builds.
  #
  # @api public
  sig { returns(T::Array[String]) }
  def std_meson_args
    ["--prefix=#{prefix}", "--libdir=#{lib}", "--buildtype=release", "--wrap-mode=nofallback"]
  end

  # Standard parameters for npm builds.
  #
  # @param prefix [String, Pathname, false] installation prefix (default: libexec)
  # @param ignore_scripts [Boolean] whether to add --ignore-scripts flag (default: true)
  # @api public
  sig { params(prefix: T.any(String, Pathname, FalseClass), ignore_scripts: T::Boolean).returns(T::Array[String]) }
  def std_npm_args(prefix: libexec, ignore_scripts: true)
    require "language/node"

    return Language::Node.std_npm_install_args(Pathname(prefix), ignore_scripts:) if prefix

    Language::Node.local_npm_install_args(ignore_scripts:)
  end

  # Standard parameters for pip builds.
  #
  # @api public
  sig {
    params(prefix:          T.any(FalseClass, String, Pathname),
           build_isolation: T::Boolean).returns(T::Array[String])
  }
  def std_pip_args(prefix: self.prefix, build_isolation: false)
    args = ["--verbose", "--no-deps", "--no-binary=:all:", "--ignore-installed", "--no-compile"]
    # Delay packages published in the last day so builds are less likely to
    # install a freshly compromised PyPI release.
    args << "--uploaded-prior-to=#{(Time.now.utc - (24 * 60 * 60)).iso8601(0)}"
    args << "--prefix=#{prefix}" if prefix
    args << "--no-build-isolation" unless build_isolation
    args
  end

  # Standard parameters for Zig builds.
  #
  # `release_mode` can be set to either `:safe`, `:fast` or `:small`,
  # with `:fast` being the default value.
  #
  # @api public
  sig {
    params(prefix:       T.any(String, Pathname),
           release_mode: Symbol).returns(T::Array[String])
  }
  def std_zig_args(prefix: self.prefix, release_mode: :fast)
    raise ArgumentError, "Invalid Zig release mode: #{release_mode}" if [:safe, :fast, :small].exclude?(release_mode)

    release_mode_downcased = release_mode.to_s.downcase
    release_mode_capitalized = release_mode.to_s.capitalize
    [
      "--prefix", prefix.to_s,
      "--release=#{release_mode_downcased}",
      "-Doptimize=Release#{release_mode_capitalized}",
      "--summary", "all"
    ]
  end

  # Shared library names according to platform conventions.
  #
  # Optionally specify a `version` to restrict the shared library to a specific
  # version. The special string "*" matches any version.
  #
  # If `name` is specified as "*", match any shared library of any version.
  #
  # ### Example
  #
  # ```ruby
  # shared_library("foo")      #=> foo.dylib
  # shared_library("foo", 1)   #=> foo.1.dylib
  # shared_library("foo", "*") #=> foo.2.dylib, foo.1.dylib, foo.dylib
  # shared_library("*")        #=> foo.dylib, bar.dylib
  # ```
  #
  # @api public
  sig { params(name: String, version: T.nilable(T.any(String, Integer))).returns(String) }
  def shared_library(name, version = nil)
    return "*.dylib" if name == "*" && (version.blank? || version == "*")

    infix = if version == "*"
      "{,.*}"
    elsif version.present?
      ".#{version}"
    end
    "#{name}#{infix}.dylib"
  end

  # Executable/Library RPATH according to platform conventions.
  #
  # Optionally specify a `source` or `target` depending on the location
  # of the file containing the RPATH command and where its target is located.
  #
  # ### Example
  #
  # ```ruby
  # rpath #=> "@loader_path/../lib"
  # rpath(target: frameworks) #=> "@loader_path/../Frameworks"
  # rpath(source: libexec/"bin") #=> "@loader_path/../../lib"
  # ```
  #
  # @api public
  sig { params(source: Pathname, target: Pathname).returns(String) }
  def rpath(source: bin, target: lib)
    unless target.to_s.start_with?(HOMEBREW_PREFIX)
      raise "rpath `target` should only be used for paths inside `$HOMEBREW_PREFIX`!"
    end

    "#{loader_path}/#{target.relative_path_from(source)}"
  end

  # Linker variable for the directory containing the program or shared object.
  #
  # @api public
  sig { returns(String) }
  def loader_path = "@loader_path"

  # Creates a new `Time` object for use in the formula as the build time.
  #
  # @see https://www.rubydoc.info/stdlib/time/Time Time
  sig { returns(Time) }
  def time
    if ENV["SOURCE_DATE_EPOCH"].present?
      Time.at(ENV["SOURCE_DATE_EPOCH"].to_i).utc
    else
      Time.now.utc
    end
  end

  # Replaces a universal binary with its native slice.
  #
  # If called with no parameters, does this with all compatible
  # universal binaries in a {Formula}'s {Keg}.
  #
  # Raises an error if no universal binaries are found to deuniversalize.
  #
  # @api public
  sig { params(targets: T.nilable(T.any(Pathname, String))).void }
  def deuniversalize_machos(*targets)
    if targets.none?
      targets = any_installed_keg&.mach_o_files&.select do |file|
        file.arch == :universal && file.archs.include?(Hardware::CPU.arch)
      end
    end

    raise "No universal binaries found to deuniversalize" if targets.blank?

    targets.compact.each do |target|
      target = MachOPathname.wrap(target)
      extract_macho_slice_from(target, Hardware::CPU.arch)
    end
  end

  sig { params(file: MachOShim, arch: T.nilable(Symbol)).void }
  def extract_macho_slice_from(file, arch = Hardware::CPU.arch)
    odebug "Extracting #{arch} slice from #{file}"
    file.ensure_writable do
      macho = MachO::FatFile.new(file)
      native_slice = macho.extract(Hardware::CPU.arch)
      native_slice.write file
      MachO.codesign! file if Hardware::CPU.arm?
    rescue MachO::MachOBinaryError
      onoe "#{file} is not a universal binary"
      raise
    rescue NoMethodError
      onoe "#{file} does not contain an #{arch} slice"
      raise
    end
  end
  private :extract_macho_slice_from

  # Generate shell completions for a formula for `bash`, `zsh`, `fish`, and
  # optionally `pwsh` using the formula's executable.
  #
  # ### Examples
  #
  # Using default values for optional arguments.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions")
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "bash")
  # (zsh_completion/"_foo").write Utils.safe_popen_read({ "SHELL" => "zsh" }, bin/"foo", "completions", "zsh")
  # (fish_completion/"foo.fish").write Utils.safe_popen_read({ "SHELL" => "fish" }, bin/"foo",
  #                                                          "completions", "fish")
  # ```
  #
  # If your executable can generate completions for PowerShell,
  # you must pass ":pwsh" explicitly along with any other supported shells.
  # This will pass "powershell" as the completion argument.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shells: [:bash, :pwsh])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "bash")
  # (pwsh_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "pwsh" }, bin/"foo",
  #                                                           "completions", "powershell")
  # ```
  #
  # Selecting shells and using a different `base_name`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shells: [:bash, :zsh], base_name: "bar")
  #
  # # translates to
  # (bash_completion/"bar").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "bash")
  # (zsh_completion/"_bar").write Utils.safe_popen_read({ "SHELL" => "zsh" }, bin/"foo", "completions", "zsh")
  # ```
  #
  # Using predefined `shell_parameter_format :arg`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: :arg, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo",
  #                                                     "completions", "--shell=bash")
  # ```
  #
  # Using predefined `shell_parameter_format :clap`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", shell_parameter_format: :clap, shells: [:zsh])
  #
  # # translates to
  # (zsh_completion/"_foo").write Utils.safe_popen_read({ "SHELL" => "zsh", "COMPLETE" => "zsh" }, bin/"foo")
  # ```
  #
  # Using predefined `shell_parameter_format :click`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", shell_parameter_format: :click, shells: [:zsh])
  #
  # # translates to
  # (zsh_completion/"_foo").write Utils.safe_popen_read({ "SHELL" => "zsh", "_FOO_COMPLETE" => "zsh_source" },
  #                                                     bin/"foo")
  # ```
  #
  # Using predefined `shell_parameter_format :cobra`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", shell_parameter_format: :cobra, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completion", "bash")
  # ```
  #
  # Using predefined `shell_parameter_format :flag`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: :flag, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions", "--bash")
  # ```
  #
  # Using predefined `shell_parameter_format :none`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: :none, shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo", "completions")
  # ```
  #
  # Using predefined `shell_parameter_format :typer`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", shell_parameter_format: :typer, shells: [:zsh])
  #
  # # translates to
  # (zsh_completion/"_foo").write Utils.safe_popen_read(
  #   { "SHELL" => "zsh", "_TYPER_COMPLETE_TEST_DISABLE_SHELL_DETECTION" => "1" },
  #   bin/"foo", "--show-completion", "zsh"
  # )
  # ```
  #
  # Using custom `shell_parameter_format`.
  #
  # ```ruby
  # generate_completions_from_executable(bin/"foo", "completions", shell_parameter_format: "--selected-shell=",
  #                                      shells: [:bash])
  #
  # # translates to
  # (bash_completion/"foo").write Utils.safe_popen_read({ "SHELL" => "bash" }, bin/"foo",
  #                                                     "completions", "--selected-shell=bash")
  # ```
  #
  # @api public
  # @param commands
  #   the path to the executable and any passed subcommand(s) to use for generating the completion scripts.
  # @param base_name
  #   the base name of the generated completion script. Defaults to the name of the executable if installed
  #   within formula's bin or sbin. Otherwise falls back to the formula name.
  # @param shell_parameter_format
  #   specify how `shells` should each be passed to the `executable`. Takes either a String representing a
  #   prefix, or one of `[:arg, :clap, :click, :cobra, :flag, :none, :typer]`.
  #   Defaults to plainly passing the shell.
  # @param shells
  #   the shells to generate completion scripts for. Defaults to `[:bash, :zsh, :fish]`.
  sig {
    params(
      commands:               T.any(Pathname, String),
      base_name:              T.nilable(String),
      shell_parameter_format: T.nilable(T.any(Symbol, String)),
      shells:                 T::Array[Symbol],
    ).void
  }
  def generate_completions_from_executable(*commands,
                                           base_name: nil,
                                           shell_parameter_format: nil,
                                           shells: Utils::ShellCompletion.default_completion_shells(shell_parameter_format))
    executable = commands.first.to_s
    base_name ||= File.basename(executable) if executable.start_with?(bin.to_s, sbin.to_s)
    base_name ||= name

    completion_script_path_map = {
      bash: bash_completion/base_name,
      zsh:  zsh_completion/"_#{base_name}",
      fish: fish_completion/"#{base_name}.fish",
      pwsh: pwsh_completion/"_#{base_name}.ps1",
    }

    shells.each do |shell|
      popen_read_env = { "SHELL" => shell.to_s }
      script_path = completion_script_path_map[shell]

      shell_parameter = Utils::ShellCompletion.completion_shell_parameter(
        shell_parameter_format,
        shell,
        executable,
        popen_read_env,
      )

      script_path.dirname.mkpath
      script_path.write Utils::ShellCompletion.generate_completion_output(commands, shell_parameter, popen_read_env)
    end
  end

  # An array of all core {Formula} names.
  sig { returns(T::Array[String]) }
  def self.core_names
    CoreTap.instance.formula_names
  end

  # An array of all tap {Formula} names.
  sig { returns(T::Array[String]) }
  def self.tap_names
    @tap_names ||= T.let(Tap.reject(&:core_tap?).flat_map(&:formula_names).sort, T.nilable(T::Array[String]))
  end

  # An array of all tap {Formula} files.
  sig { returns(T::Array[Pathname]) }
  def self.tap_files
    @tap_files ||= T.let(Tap.reject(&:core_tap?).flat_map(&:formula_files), T.nilable(T::Array[Pathname]))
  end

  # An array of all {Formula} names.
  sig { returns(T::Array[String]) }
  def self.names
    @names ||= T.let((core_names + tap_names.map do |name|
      name.split("/").fetch(-1)
    end).uniq.sort, T.nilable(T::Array[String]))
  end

  # An array of all {Formula} names, which the tap formulae have as the fully-qualified name.
  sig { returns(T::Array[String]) }
  def self.full_names
    @full_names ||= T.let(core_names + tap_names, T.nilable(T::Array[String]))
  end

  # An array of each known {Formula}.
  # Can only be used when users specify `--eval-all` with a command or set `HOMEBREW_EVAL_ALL=1`.
  sig { params(eval_all: T::Boolean).returns(T::Array[Formula]) }
  def self.all(eval_all: false)
    if !eval_all && !Homebrew::EnvConfig.eval_all?
      raise ArgumentError, "Formula#all cannot be used without `--eval-all` or `HOMEBREW_EVAL_ALL=1`"
    end

    (core_names + tap_files).filter_map do |name_or_file|
      Formulary.factory(name_or_file)
    rescue FormulaUnavailableError, FormulaUnreadableError, FormulaSpecificationError => e
      # Don't let one broken formula break commands. But do complain.
      onoe "Failed to import: #{name_or_file}"
      $stderr.puts e

      nil
    end
  end

  # An array of all racks currently installed.
  sig { returns(T::Array[Pathname]) }
  def self.racks
    Formula.cache[:racks] ||= if HOMEBREW_CELLAR.directory?
      HOMEBREW_CELLAR.subdirs.reject do |rack|
        rack.symlink? || rack.basename.to_s.start_with?(".") || rack.subdirs.empty?
      end
    else
      []
    end
  end

  # An array of all currently installed formula names.
  sig { returns(T::Array[String]) }
  def self.installed_formula_names
    racks.map { |rack| rack.basename.to_s }
  end

  # An array of all installed {Formula}e.
  sig { returns(T::Array[Formula]) }
  def self.installed
    Formula.cache[:installed] ||= racks.flat_map do |rack|
      Formulary.from_rack(rack)
    rescue
      []
    end.uniq(&:name)
  end

  sig { params(alias_path: T.nilable(Pathname)).returns(T::Array[Formula]) }
  def self.installed_with_alias_path(alias_path)
    return [] if alias_path.nil?

    installed.select { |f| f.installed_alias_path == alias_path }
  end

  # An array of all alias files of core {Formula}e.
  sig { returns(T::Array[Pathname]) }
  def self.core_alias_files
    CoreTap.instance.alias_files
  end

  # An array of all core aliases.
  sig { returns(T::Array[String]) }
  def self.core_aliases
    CoreTap.instance.aliases
  end

  # An array of all tap aliases.
  sig { returns(T::Array[String]) }
  def self.tap_aliases
    @tap_aliases ||= T.let(Tap.reject(&:core_tap?).flat_map(&:aliases).sort, T.nilable(T::Array[String]))
  end

  # An array of all aliases.
  sig { returns(T::Array[String]) }
  def self.aliases
    @aliases ||= T.let((core_aliases + tap_aliases.map do |name|
      name.split("/").fetch(-1)
    end).uniq.sort, T.nilable(T::Array[String]))
  end

  # An array of all aliases as fully-qualified names.
  sig { returns(T::Array[String]) }
  def self.alias_full_names
    @alias_full_names ||= T.let(core_aliases + tap_aliases, T.nilable(T::Array[String]))
  end

  # Returns a list of approximately matching formula names, but not the complete match.
  sig { params(name: String).returns(T::Array[String]) }
  def self.fuzzy_search(name)
    @spell_checker ||= T.let(DidYouMean::SpellChecker.new(dictionary: Set.new(names + full_names).to_a),
                             T.nilable(DidYouMean::SpellChecker))
    T.cast(@spell_checker.correct(name), T::Array[String])
  end

  sig { params(name: T.any(Pathname, String)).returns(Formula) }
  def self.[](name)
    Formulary.factory(name)
  end

  # True if this formula is provided by Homebrew itself.
  sig { returns(T::Boolean) }
  def core_formula?
    !!tap&.core_tap?
  end

  # True if this formula is provided by an external {Tap}.
  sig { returns(T::Boolean) }
  def tap?
    return false unless tap

    !T.must(tap).core_tap?
  end

  # True if this formula can be installed on this platform.
  # Redefined in `extend/os`.
  sig { returns(T::Boolean) }
  def valid_platform?
    requirements.none?(MacOSRequirement) && requirements.none?(LinuxRequirement)
  end

  sig { params(options: T::Hash[Symbol, String]).void }
  def print_tap_action(options = {})
    return unless tap?

    verb = options[:verb] || "Installing"
    ohai "#{verb} #{name} from #{tap}"
  end

  sig { returns(T.nilable(String)) }
  def tap_git_head
    tap&.git_head
  rescue TapUnavailableError
    nil
  end

  delegate env: :"self.class"

  # Returns a list of {FormulaConflict} objects indicating any
  # formulae that conflict with this one and why.
  #
  # @api internal
  sig { returns(T::Array[FormulaConflict]) }
  def conflicts = T.must(self.class.conflicts)

  # Returns a list of {Dependency} objects in an installable order, which
  # means if `a` depends on `b` then `b` will be ordered before `a` in this list.
  #
  # @api internal
  sig { params(block: T.nilable(T.proc.params(arg0: Formula, arg1: Dependency).void)).returns(T::Array[Dependency]) }
  def recursive_dependencies(&block)
    cache_key = "Formula#recursive_dependencies"
    if block
      cache_key += "-#{full_name}"
      cache_timestamp = Time.now
    end
    Dependency.expand(self, cache_key:, cache_timestamp:, &block)
  ensure
    Dependency.delete_timestamped_cache_entry(cache_key, cache_timestamp) if block
  end

  # The full set of {Requirements} for this formula's dependency tree.
  #
  # @api internal
  sig { params(block: T.nilable(T.proc.params(arg0: Formula, arg1: Requirement).void)).returns(Requirements) }
  def recursive_requirements(&block)
    cache_key = "Formula#recursive_requirements" unless block
    Requirement.expand(self, cache_key:, &block)
  end

  # Returns a {Keg} for the `opt_prefix` or `installed_prefix` if they exist.
  # If not, return `nil`.
  sig { returns(T.nilable(Keg)) }
  def any_installed_keg
    Formula.cache[:any_installed_keg] ||= {}
    Formula.cache[:any_installed_keg][full_name] ||= if (installed_prefix = any_installed_prefix)
      Keg.new(installed_prefix)
    end
  end

  # Get the path of any installed prefix.
  #
  # @api internal
  sig { returns(T.nilable(Pathname)) }
  def any_installed_prefix
    if optlinked? && opt_prefix.exist?
      opt_prefix
    elsif (latest_installed_prefix = installed_prefixes.last)
      latest_installed_prefix
    end
  end

  # Returns the {PkgVersion} for this formula if it is installed.
  # If not, return `nil`.
  sig { returns(T.nilable(PkgVersion)) }
  def any_installed_version
    any_installed_keg&.version
  end

  # Returns a list of {Dependency} objects that are required at runtime.
  #
  # @api internal
  sig { params(read_from_tab: T::Boolean, undeclared: T::Boolean).returns(T::Array[Dependency]) }
  def runtime_dependencies(read_from_tab: true, undeclared: true)
    cache_key = "#{full_name}-#{read_from_tab}-#{undeclared}"

    Formula.cache[:runtime_dependencies] ||= {}
    Formula.cache[:runtime_dependencies][cache_key] ||= begin
      deps = if read_from_tab && undeclared &&
                (tab_deps = any_installed_keg&.runtime_dependencies)
        tab_deps.filter_map do |d|
          full_name = d["full_name"]
          next unless full_name

          Dependency.new full_name
        end
      end
      begin
        deps ||= declared_runtime_dependencies unless undeclared
        deps ||= (declared_runtime_dependencies | undeclared_runtime_dependencies)
      rescue FormulaUnavailableError
        onoe "Could not get runtime dependencies from #{path}!"
        deps ||= []
      end
      deps
    end
  end

  # Returns a list of {Formula} objects that are required at runtime.
  sig { params(read_from_tab: T::Boolean, undeclared: T::Boolean).returns(T::Array[Formula]) }
  def runtime_formula_dependencies(read_from_tab: true, undeclared: true)
    cache_key = "#{full_name}-#{read_from_tab}-#{undeclared}"

    Formula.cache[:runtime_formula_dependencies] ||= {}
    Formula.cache[:runtime_formula_dependencies][cache_key] ||= runtime_dependencies(
      read_from_tab:,
      undeclared:,
    ).filter_map do |d|
      d.to_formula
    rescue FormulaUnavailableError
      nil
    end
  end

  # Returns a list of installed {Formula} objects that are required at runtime.
  sig { params(read_from_tab: T::Boolean, undeclared: T::Boolean).returns(T::Array[Formula]) }
  def installed_runtime_formula_dependencies(read_from_tab: true, undeclared: true)
    cache_key = "#{full_name}-#{read_from_tab}-#{undeclared}"

    Formula.cache[:installed_runtime_formula_dependencies] ||= {}
    Formula.cache[:installed_runtime_formula_dependencies][cache_key] ||= runtime_dependencies(
      read_from_tab:,
      undeclared:,
    ).filter_map do |d|
      d.to_installed_formula
    rescue FormulaUnavailableError
      nil
    end
  end

  sig { returns(T::Array[Formula]) }
  def runtime_installed_formula_dependents
    # `any_installed_keg` and `runtime_dependencies` `select`s ensure
    # that we don't end up with something `Formula#runtime_dependencies` can't
    # read from a `Tab`.
    Formula.cache[:runtime_installed_formula_dependents] ||= {}
    Formula.cache[:runtime_installed_formula_dependents][full_name] ||= Formula.installed
                                                                               .select(&:any_installed_keg)
                                                                               .select(&:runtime_dependencies)
                                                                               .select do |f|
      f.installed_runtime_formula_dependencies.any? do |dep|
        full_name == dep.full_name
      rescue
        name == dep.name
      end
    end
  end

  # Returns a list of formulae depended on by this formula that aren't
  # installed. Only trusts tab data for dependency information; when the tab
  # has no runtime dependency data (nil or empty), returns empty rather
  # than falling back to formula definitions.
  # This prevents stale or missing tab data from incorrectly blocking
  # uninstalls.
  sig { params(hide: T::Array[String]).returns(T::Array[Dependency]) }
  def missing_dependencies(hide: [])
    tab_deps = any_installed_keg&.runtime_dependencies
    return [] if tab_deps.blank?

    tab_deps.filter_map do |d|
      full_name = d["full_name"]
      next if full_name.blank?

      dep = Dependency.new(full_name)
      dep if hide.include?(dep.name) || dep.to_installed_formula.installed_prefixes.none?
    rescue FormulaUnavailableError
      nil
    end
  end

  sig { returns(T.nilable(String)) }
  def ruby_source_path
    path.relative_path_from(T.must(tap).path).to_s if tap && path.exist?
  end

  sig { returns(T.nilable(Checksum)) }
  def ruby_source_checksum
    Checksum.new(Digest::SHA256.file(path).hexdigest) if path.exist?
  end

  sig { params(dependables: T::Hash[Symbol, T.untyped]).returns(T::Array[T::Hash[Symbol, T.untyped]]) }
  def merge_spec_dependables(dependables)
    # We have a hash of specs names (stable/head) to dependency lists.
    # Merge all of the dependency lists together, removing any duplicates.
    all_dependables = [].union(*dependables.values.map(&:to_a))

    all_dependables.map do |dependable|
      {
        dependable:,
        # Now find the list of specs each dependency was a part of.
        specs:      dependables.filter_map { |spec, spec_deps| spec if spec_deps&.include?(dependable) },
      }
    end
  end
  private :merge_spec_dependables

  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash
    hsh = {
      "name"                            => name,
      "full_name"                       => full_name,
      "tap"                             => tap&.name,
      "oldnames"                        => oldnames,
      "aliases"                         => aliases.sort,
      "versioned_formulae"              => versioned_formulae.map(&:name),
      "desc"                            => desc,
      "license"                         => SPDX.license_expression_to_string(license),
      "homepage"                        => homepage,
      "versions"                        => {
        "stable" => stable&.version&.to_s,
        "head"   => head&.version&.to_s,
        "bottle" => bottle_defined?,
      },
      "urls"                            => urls_hash,
      "revision"                        => revision,
      "version_scheme"                  => version_scheme,
      "compatibility_version"           => compatibility_version,
      "autobump"                        => autobump?,
      "no_autobump_message"             => no_autobump_message,
      "skip_livecheck"                  => livecheck.skip?,
      "bottle"                          => {},
      "pour_bottle_only_if"             => self.class.pour_bottle_only_if&.to_s,
      "keg_only"                        => keg_only?,
      "keg_only_reason"                 => keg_only_reason&.to_hash,
      "options"                         => [],
      "build_dependencies"              => [],
      "dependencies"                    => [],
      "test_dependencies"               => [],
      "recommended_dependencies"        => [],
      "optional_dependencies"           => [],
      "uses_from_macos"                 => [],
      "uses_from_macos_bounds"          => [],
      "requirements"                    => serialized_requirements,
      "conflicts_with"                  => conflicts.map(&:name),
      "conflicts_with_reasons"          => conflicts.map(&:reason),
      "link_overwrite"                  => self.class.link_overwrite_paths.to_a,
      "caveats"                         => caveats_with_placeholders,
      "installed"                       => T.let([], T::Array[T::Hash[String, T.untyped]]),
      "linked_keg"                      => linked_version&.to_s,
      "pinned"                          => pinned?,
      "outdated"                        => outdated?,
      "deprecated"                      => deprecated?,
      "deprecation_date"                => deprecation_date,
      "deprecation_reason"              => deprecation_reason,
      "deprecation_replacement_formula" => deprecation_replacement_formula,
      "deprecation_replacement_cask"    => deprecation_replacement_cask,
      "deprecate_args"                  => deprecate_args,
      "disabled"                        => disabled?,
      "disable_date"                    => disable_date,
      "disable_reason"                  => disable_reason,
      "disable_replacement_formula"     => disable_replacement_formula,
      "disable_replacement_cask"        => disable_replacement_cask,
      "disable_args"                    => disable_args,
      "post_install_defined"            => post_install_defined?,
      "service"                         => (service.to_hash if service?),
      "tap_git_head"                    => tap_git_head,
      "ruby_source_path"                => ruby_source_path,
      "ruby_source_checksum"            => {},
    }

    hsh["bottle"]["stable"] = bottle_hash if stable && bottle_defined?

    hsh["options"] = options.map do |opt|
      { "option" => opt.flag, "description" => opt.description }
    end

    hsh.merge!(dependencies_hash)

    hsh["installed"] = installed_kegs.sort_by(&:scheme_and_version).map do |keg|
      tab = keg.tab
      {
        "version"                 => keg.version.to_s,
        "used_options"            => tab.used_options.as_flags,
        "built_as_bottle"         => tab.built_as_bottle,
        "poured_from_bottle"      => tab.poured_from_bottle,
        "time"                    => tab.time,
        "runtime_dependencies"    => tab.runtime_dependencies,
        "installed_as_dependency" => tab.installed_as_dependency,
        "installed_on_request"    => tab.installed_on_request,
      }
    end

    if (source_checksum = ruby_source_checksum)
      hsh["ruby_source_checksum"] = {
        "sha256" => source_checksum.hexdigest,
      }
    end

    hsh
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def to_hash_with_variations
    if loaded_from_internal_api?
      raise UsageError, "Cannot call #to_hash_with_variations on formulae loaded from the internal API"
    end

    hash = to_hash

    # Take from API, merging in local install status.
    if loaded_from_api? && (json_formula = api_source) && !Homebrew::EnvConfig.no_install_from_api?
      return json_formula.dup.merge(
        hash.slice("name", "installed", "linked_keg", "pinned", "outdated"),
      )
    end

    variations = {}

    if path.exist? && on_system_blocks_exist?
      formula_contents = path.read
      OnSystem::VALID_OS_ARCH_TAGS.each do |bottle_tag|
        Homebrew::SimulateSystem.with_tag(bottle_tag) do
          variations_namespace = Formulary.class_s("Variations#{bottle_tag.to_sym.capitalize}")
          variations_formula_class = Formulary.load_formula(name, path, formula_contents, variations_namespace,
                                                            flags: self.class.build_flags, ignore_errors: true)
          variations_formula = variations_formula_class.new(name, path, :stable,
                                                            alias_path:, force_bottle:)

          variations_formula.to_hash.each do |key, value|
            next if value.to_s == hash[key].to_s

            variations[bottle_tag.to_sym] ||= {}
            variations[bottle_tag.to_sym][key] = value
          end
        end
      end
    end

    hash["variations"] = variations
    hash
  end

  # Returns the bottle information for a formula.
  sig { returns(T::Hash[String, T.untyped]) }
  def bottle_hash
    hash = {}
    stable_spec = stable
    return hash unless stable_spec
    return hash unless bottle_defined?

    bottle_spec = stable_spec.bottle_specification

    hash["rebuild"] = bottle_spec.rebuild
    hash["root_url"] = bottle_spec.root_url
    hash["files"] = {}

    bottle_spec.collector.each_tag do |tag|
      tag_spec = bottle_spec.collector.specification_for(tag, no_older_versions: true)
      odie "Specification for tag #{tag} is nil" if tag_spec.nil?

      os_cellar = tag_spec.cellar
      os_cellar = os_cellar.inspect if os_cellar.is_a?(Symbol)
      checksum = tag_spec.checksum.hexdigest

      file_hash = {}
      file_hash["cellar"] = os_cellar
      filename = Bottle::Filename.create(self, tag, bottle_spec.rebuild)
      path, = Utils::Bottles.path_resolved_basename(bottle_spec.root_url, name, checksum, filename)
      file_hash["url"] = "#{bottle_spec.root_url}/#{path}"
      file_hash["sha256"] = checksum

      hash["files"][tag.to_sym] = file_hash
    end
    hash
  end

  sig { returns(T::Hash[String, T::Hash[String, T.untyped]]) }
  def urls_hash
    hash = {}

    if stable
      stable_spec = T.must(stable)
      hash["stable"] = {
        "url"      => stable_spec.url,
        "tag"      => stable_spec.specs[:tag],
        "revision" => stable_spec.specs[:revision],
        "using"    => (stable_spec.using if stable_spec.using.is_a?(Symbol)),
        "checksum" => stable_spec.checksum&.to_s,
      }
    end

    if head
      hash["head"] = {
        "url"    => T.must(head).url,
        "branch" => T.must(head).specs[:branch],
        "using"  => (T.must(head).using if T.must(head).using.is_a?(Symbol)),
      }
    end

    hash
  end

  sig { returns(T::Array[T::Hash[String, T.untyped]]) }
  def serialized_requirements
    requirements = self.class.spec_syms.to_h do |sym|
      [sym, send(sym)&.requirements]
    end

    merge_spec_dependables(requirements).map do |data|
      req = data[:dependable]
      req_name = req.name.dup
      req_name.prepend("maximum_") if req.respond_to?(:comparator) && req.comparator == "<="
      req_version = if req.respond_to?(:version)
        req.version
      elsif req.respond_to?(:arch)
        req.arch
      end
      {
        "name"     => req_name,
        "cask"     => req.cask,
        "download" => req.download,
        "version"  => req_version,
        "contexts" => req.tags,
        "specs"    => data[:specs],
      }
    end
  end

  sig { returns(T.nilable(String)) }
  def caveats_with_placeholders
    caveats&.gsub(HOMEBREW_PREFIX, HOMEBREW_PREFIX_PLACEHOLDER)
           &.gsub(HOMEBREW_CELLAR, HOMEBREW_CELLAR_PLACEHOLDER)
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def dependencies_hash
    # Create a hash of spec names (stable/head) to the list of dependencies under each
    dependencies = self.class.spec_syms.to_h do |sym|
      [sym, send(sym)&.declared_deps]
    end

    # Implicit dependencies are only needed when installing from source
    # since they are only used to download and unpack source files.
    # @see DependencyCollector
    dependencies.transform_values! { |deps| deps&.reject(&:implicit?) }

    hash = {}

    dependencies.each do |spec_sym, spec_deps|
      next if spec_deps.nil?

      dep_hash = if spec_sym == :stable
        hash
      else
        next if spec_deps == dependencies[:stable]

        hash["#{spec_sym}_dependencies"] ||= {}
      end

      dep_hash["build_dependencies"] = spec_deps.select(&:build?)
                                                .reject(&:uses_from_macos?)
                                                .map(&:name)
                                                .uniq
      dep_hash["dependencies"] = spec_deps.reject(&:optional?)
                                          .reject(&:recommended?)
                                          .reject(&:build?)
                                          .reject(&:test?)
                                          .reject(&:uses_from_macos?)
                                          .map(&:name)
                                          .uniq
      dep_hash["test_dependencies"] = spec_deps.select(&:test?)
                                     
