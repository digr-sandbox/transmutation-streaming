# frozen_string_literal: true

# :markup: markdown

require "active_support/core_ext/hash/slice"
require "active_support/core_ext/enumerable"
require "active_support/core_ext/array/extract_options"
require "active_support/core_ext/regexp"
require "action_dispatch/routing/redirection"
require "action_dispatch/routing/endpoint"

module ActionDispatch
  module Routing
    class Mapper
      class BacktraceCleaner < ActiveSupport::BacktraceCleaner # :nodoc:
        def initialize
          super
          remove_silencers!
          add_core_silencer
          add_stdlib_silencer
        end
      end

      URL_OPTIONS = [:protocol, :subdomain, :domain, :host, :port]

      cattr_accessor :route_source_locations, instance_accessor: false, default: false
      cattr_accessor :backtrace_cleaner, instance_accessor: false, default: BacktraceCleaner.new

      class Constraints < Routing::Endpoint # :nodoc:
        attr_reader :app, :constraints

        SERVE = ->(app, req) { app.serve req }
        CALL  = ->(app, req) { app.call req.env }

        def initialize(app, constraints, strategy)
          # Unwrap Constraints objects. I don't actually think it's possible to pass a
          # Constraints object to this constructor, but there were multiple places that
          # kept testing children of this object. I **think** they were just being
          # defensive, but I have no idea.
          if app.is_a?(self.class)
            constraints += app.constraints
            app = app.app
          end

          @strategy = strategy

          @app, @constraints, = app, constraints
        end

        def dispatcher?; @strategy == SERVE; end

        def matches?(req)
          @constraints.all? do |constraint|
            (constraint.respond_to?(:matches?) && constraint.matches?(req)) ||
              (constraint.respond_to?(:call) && constraint.call(*constraint_args(constraint, req)))
          end
        end

        def serve(req)
          return [ 404, { Constants::X_CASCADE => "pass" }, [] ] unless matches?(req)

          @strategy.call @app, req
        end

        private
          def constraint_args(constraint, request)
            arity = if constraint.respond_to?(:arity)
              constraint.arity
            else
              constraint.method(:call).arity
            end

            if arity < 1
              []
            elsif arity == 1
              [request]
            else
              [request.path_parameters, request]
            end
          end
      end

      class Mapping # :nodoc:
        ANCHOR_CHARACTERS_REGEX = %r{\A(\\A|\^)|(\\Z|\\z|\$)\Z}
        OPTIONAL_FORMAT_REGEX = %r{(?:\(\.:format\)+|\.:format|/)\Z}

        attr_reader :path, :requirements, :defaults, :to, :default_controller,
                    :default_action, :required_defaults, :ast, :scope_options

        def self.build(scope, set, ast, controller, default_action, to, via, formatted, options_constraints, anchor, internal, options)
          scope_params = {
            blocks: scope[:blocks] || [],
            constraints: scope[:constraints] || {},
            defaults: (scope[:defaults] || {}).dup,
            module: scope[:module],
            options: scope[:options] || {}
          }

          new set: set, ast: ast, controller: controller, default_action: default_action,
              to: to, formatted: formatted, via: via, options_constraints: options_constraints,
              anchor: anchor, scope_params: scope_params, internal: internal, options: scope_params[:options].merge(options)
        end

        def self.check_via(via)
          if via.empty?
            msg = "You should not use the `match` method in your router without specifying an HTTP method.\n" \
              "If you want to expose your action to both GET and POST, add `via: [:get, :post]` option.\n" \
              "If you want to expose your action to GET, use `get` in the router:\n" \
              "  Instead of: match \"controller#action\"\n" \
              "  Do: get \"controller#action\""
            raise ArgumentError, msg
          end
          via
        end

        def self.normalize_path(path, format)
          path = Mapper.normalize_path(path)

          if format == true
            "#{path}.:format"
          elsif optional_format?(path, format)
            "#{path}(.:format)"
          else
            path
          end
        end

        def self.optional_format?(path, format)
          format != false && !path.match?(OPTIONAL_FORMAT_REGEX)
        end

        def initialize(set:, ast:, controller:, default_action:, to:, formatted:, via:, options_constraints:, anchor:, scope_params:, internal:, options:)
          @defaults           = scope_params[:defaults]
          @set                = set
          @to                 = intern(to)
          @default_controller = intern(controller)
          @default_action     = intern(default_action)
          @anchor             = anchor
          @via                = via
          @internal           = internal
          @scope_options      = scope_params[:options]
          ast                 = Journey::Ast.new(ast, formatted)

          options = ast.wildcard_options.merge!(options)

          options = normalize_options!(options, ast.path_params, scope_params[:module])

          split_options = constraints(options, ast.path_params)

          constraints = scope_params[:constraints].merge Hash[split_options[:constraints] || []]

          if options_constraints.is_a?(Hash)
            @defaults = Hash[options_constraints.find_all { |key, default|
              URL_OPTIONS.include?(key) && (String === default || Integer === default)
            }].merge @defaults
            @blocks = scope_params[:blocks]
            constraints.merge! options_constraints
          else
            @blocks = blocks(options_constraints)
          end

          requirements, conditions = split_constraints ast.path_params, constraints
          verify_regexp_requirements requirements, ast.wildcard_options

          formats = normalize_format(formatted)

          @requirements = formats[:requirements].merge Hash[requirements]
          @conditions = Hash[conditions]
          @defaults = formats[:defaults].merge(@defaults).merge(normalize_defaults(options))

          if ast.path_params.include?(:action) && !@requirements.key?(:action)
            @defaults[:action] ||= "index"
          end

          @required_defaults = (split_options[:required_defaults] || []).map(&:first)

          ast.requirements = @requirements
          @path = Journey::Path::Pattern.new(ast, @requirements, JOINED_SEPARATORS, @anchor)
        end

        JOINED_SEPARATORS = SEPARATORS.join # :nodoc:

        def make_route(name, precedence)
          Journey::Route.new(name: name, app: application, path: path, constraints: conditions,
                             required_defaults: required_defaults, defaults: defaults,
                             via: @via, precedence: precedence,
                             scope_options: scope_options, internal: @internal, source_location: route_source_location)
        end

        def application
          app(@blocks)
        end

        def conditions
          build_conditions @conditions, @set.request_class
        end

        def build_conditions(current_conditions, request_class)
          conditions = current_conditions.dup

          conditions.keep_if do |k, _|
            request_class.public_method_defined?(k)
          end
        end
        private :build_conditions

        private
          def intern(object)
            object.is_a?(String) ? -object : object
          end

          def normalize_options!(options, path_params, modyoule)
            if path_params.include?(:controller)
              raise ArgumentError, ":controller segment is not allowed within a namespace block" if modyoule

              # Add a default constraint for :controller path segments that matches namespaced
              # controllers with default routes like :controller/:action/:id(.:format), e.g:
              # GET /admin/products/show/1
              # # > { controller: 'admin/products', action: 'show', id: '1' }
              options[:controller] ||= /.+?/
            end

            if to.respond_to?(:action) || to.respond_to?(:call)
              options
            else
              if to.nil?
                controller = default_controller
                action = default_action
              elsif to.is_a?(String)
                if to.include?("#")
                  to_endpoint = to.split("#").map!(&:-@)
                  controller  = to_endpoint[0]
                  action      = to_endpoint[1]
                else
                  controller = default_controller
                  action = to
                end
              else
                raise ArgumentError, ":to must respond to `action` or `call`, or it must be a String that includes '#', or the controller should be implicit"
              end

              controller = add_controller_module(controller, modyoule)

              options.merge! check_controller_and_action(path_params, controller, action)
            end
          end

          def split_constraints(path_params, constraints)
            constraints.partition do |key, requirement|
              path_params.include?(key) || key == :controller
            end
          end

          def normalize_format(formatted)
            case formatted
            when true
              { requirements: { format: /.+/ },
                defaults:     {} }
            when Regexp
              { requirements: { format: formatted },
                defaults:     { format: nil } }
            when String
              { requirements: { format: Regexp.compile(formatted) },
                defaults:     { format: formatted } }
            else
              { requirements: {}, defaults: {} }
            end
          end

          def verify_regexp_requirements(requirements, wildcard_options)
            requirements.each do |requirement, regex|
              next unless regex.is_a? Regexp

              if ANCHOR_CHARACTERS_REGEX.match?(regex.source)
                raise ArgumentError, "Regexp anchor characters are not allowed in routing requirements: #{requirement.inspect}"
              end

              if regex.multiline?
                next if wildcard_options.key?(requirement)

                raise ArgumentError, "Regexp multiline option is not allowed in routing requirements: #{regex.inspect}"
              end
            end
          end

          def normalize_defaults(options)
            Hash[options.reject { |_, default| Regexp === default }]
          end

          def app(blocks)
            if to.respond_to?(:action)
              Routing::RouteSet::StaticDispatcher.new to
            elsif to.respond_to?(:call)
              Constraints.new(to, blocks, Constraints::CALL)
            elsif blocks.any?
              Constraints.new(dispatcher(defaults.key?(:controller)), blocks, Constraints::SERVE)
            else
              dispatcher(defaults.key?(:controller))
            end
          end

          def check_controller_and_action(path_params, controller, action)
            hash = check_part(:controller, controller, path_params, {}) do |part|
              translate_controller(part) {
                message = +"'#{part}' is not a supported controller name. This can lead to potential routing problems."
                message << " See https://guides.rubyonrails.org/routing.html#specifying-a-controller-to-use"

                raise ArgumentError, message
              }
            end

            check_part(:action, action, path_params, hash) { |part|
              part.is_a?(Regexp) ? part : part.to_s
            }
          end

          def check_part(name, part, path_params, hash)
            if part
              hash[name] = yield(part)
            else
              unless path_params.include?(name)
                message = "Missing :#{name} key on routes definition, please check your routes."
                raise ArgumentError, message
              end
            end
            hash
          end

          def add_controller_module(controller, modyoule)
            if modyoule && !controller.is_a?(Regexp)
              if controller&.start_with?("/")
                -controller[1..-1]
              else
                -[modyoule, controller].compact.join("/")
              end
            else
              controller
            end
          end

          def translate_controller(controller)
            return controller if Regexp === controller
            return controller.to_s if /\A[a-z_0-9][a-z_0-9\/]*\z/.match?(controller)

            yield
          end

          def blocks(callable_constraint)
            unless callable_constraint.respond_to?(:call) || callable_constraint.respond_to?(:matches?)
              raise ArgumentError, "Invalid constraint: #{callable_constraint.inspect} must respond to :call or :matches?"
            end
            [callable_constraint]
          end

          def constraints(options, path_params)
            options.group_by do |key, option|
              if Regexp === option
                :constraints
              else
                if path_params.include?(key)
                  :path_params
                else
                  :required_defaults
                end
              end
            end
          end

          def dispatcher(raise_on_name_error)
            Routing::RouteSet::Dispatcher.new raise_on_name_error
          end

          def route_source_location
            if Mapper.route_source_locations
              action_dispatch_dir = File.expand_path("..", __dir__)
              Thread.each_caller_location do |location|
                next if location.path.start_with?(action_dispatch_dir)

                cleaned_path = Mapper.backtrace_cleaner.clean_frame(location.path)
                next if cleaned_path.nil?

                return "#{cleaned_path}:#{location.lineno}"
              end
              nil
            end
          end
      end

      # Invokes Journey::Router::Utils.normalize_path, then ensures that /(:locale)
      # becomes (/:locale). Except for root cases, where the former is the correct
      # one.
      def self.normalize_path(path)
        path = Journey::Router::Utils.normalize_path(path)

        # the path for a root URL at this point can be something like
        # "/(/:locale)(/:platform)/(:browser)", and we would want
        # "/(:locale)(/:platform)(/:browser)" reverse "/(", "/((" etc to "(/", "((/" etc
        path.gsub!(%r{/(\(+)/?}, '\1/')
        # if a path is all optional segments, change the leading "(/" back to "/(" so it
        # evaluates to "/" when interpreted with no options. Unless, however, at least
        # one secondary segment consists of a static part, ex.
        # "(/:locale)(/pages/:page)"
        path.sub!(%r{^(\(+)/}, '/\1') if %r{^(\(+[^)]+\))(\(+/:[^)]+\))*$}.match?(path)
        path
      end

      def self.normalize_name(name)
        normalize_path(name)[1..-1].tr("/", "_")
      end

      module Base
        # Matches a URL pattern to one or more routes.
        #
        # You should not use the `match` method in your router without specifying an
        # HTTP method.
        #
        # If you want to expose your action to both GET and POST, use:
        #
        #     # sets :controller, :action, and :id in params
        #     match ':controller/:action/:id', via: [:get, :post]
        #
        # Note that `:controller`, `:action`, and `:id` are interpreted as URL query
        # parameters and thus available through `params` in an action.
        #
        # If you want to expose your action to GET, use `get` in the router:
        #
        # Instead of:
        #
        #     match ":controller/:action/:id"
        #
        # Do:
        #
        #     get ":controller/:action/:id"
        #
        # Two of these symbols are special, `:controller` maps to the controller and
        # `:action` to the controller's action. A pattern can also map wildcard segments
        # (globs) to params:
        #
        #     get 'songs/*category/:title', to: 'songs#show'
        #
        #     # 'songs/rock/classic/stairway-to-heaven' sets
        #     #  params[:category] = 'rock/classic'
        #     #  params[:title] = 'stairway-to-heaven'
        #
        # To match a wildcard parameter, it must have a name assigned to it. Without a
        # variable name to attach the glob parameter to, the route can't be parsed.
        #
        # When a pattern points to an internal route, the route's `:action` and
        # `:controller` should be set in options or hash shorthand. Examples:
        #
        #     match 'photos/:id', to: 'photos#show', via: :get
        #     match 'photos/:id', controller: 'photos', action: 'show', via: :get
        #
        # A pattern can also point to a `Rack` endpoint i.e. anything that responds to
        # `call`:
        #
        #     match 'photos/:id', to: -> (hash) { [200, {}, ["Coming soon"]] }, via: :get
        #     match 'photos/:id', to: PhotoRackApp, via: :get
        #     # Yes, controller actions are just rack endpoints
        #     match 'photos/:id', to: PhotosController.action(:show), via: :get
        #
        # Because requesting various HTTP verbs with a single action has security
        # implications, you must either specify the actions in the via options or use
        # one of the [HttpHelpers](rdoc-ref:HttpHelpers) instead `match`
        #
        # ### Options
        #
        # Any options not seen here are passed on as params with the URL.
        #
        # :controller
        # :   The route's controller.
        #
        # :action
        # :   The route's action.
        #
        # :param
        # :   Overrides the default resource identifier `:id` (name of the dynamic
        #     segment used to generate the routes). You can access that segment from
        #     your controller using `params[<:param>]`. In your router:
        #
        #         resources :users, param: :name
        #
        #     The `users` resource here will have the following routes generated for it:
        #
        #         GET       /users(.:format)
        #         POST      /users(.:format)
        #         GET       /users/new(.:format)
        #         GET       /users/:name/edit(.:format)
        #         GET       /users/:name(.:format)
        #         PATCH/PUT /users/:name(.:format)
        #         DELETE    /users/:name(.:format)
        #
        #     You can override `ActiveRecord::Base#to_param` of a related model to
        #     construct a URL:
        #
        #         class User < ActiveRecord::Base
        #           def to_param
        #             name
        #           end
        #         end
        #
        #         user = User.find_by(name: 'Phusion')
        #         user_path(user)  # => "/users/Phusion"
        #
        # :path
        # :   The path prefix for the routes.
        #
        # :module
        # :   The namespace for :controller.
        #
        #         match 'path', to: 'c#a', module: 'sekret', controller: 'posts', via: :get
        #         # => Sekret::PostsController
        #
        #     See `Scoping#namespace` for its scope equivalent.
        #
        # :as
        # :   The name used to generate routing helpers.
        #
        # :via
        # :   Allowed HTTP verb(s) for route.
        #
        #         match 'path', to: 'c#a', via: :get
        #         match 'path', to: 'c#a', via: [:get, :post]
        #         match 'path', to: 'c#a', via: :all
        #
        # :to
        # :   Points to a `Rack` endpoint. Can be an object that responds to `call` or a
        #     string representing a controller's action.
        #
        #         match 'path', to: 'controller#action', via: :get
        #         match 'path', to: -> (env) { [200, {}, ["Success!"]] }, via: :get
        #         match 'path', to: RackApp, via: :get
        #
        # :on
        # :   Shorthand for wrapping routes in a specific RESTful context. Valid values
        #     are `:member`, `:collection`, and `:new`. Only use within `resource(s)`
        #     block. For example:
        #
        #         resource :bar do
        #           match 'foo', to: 'c#a', on: :member, via: [:get, :post]
        #         end
        #
        #     Is equivalent to:
        #
        #         resource :bar do
        #           member do
        #             match 'foo', to: 'c#a', via: [:get, :post]
        #           end
        #         end
        #
        # :constraints
        # :   Constrains parameters with a hash of regular expressions or an object that
        #     responds to `matches?`. In addition, constraints other than path can also
        #     be specified with any object that responds to `===` (e.g. String, Array,
        #     Range, etc.).
        #
        #         match 'path/:id', constraints: { id: /[A-Z]\d{5}/ }, via: :get
        #
        #         match 'json_only', constraints: { format: 'json' }, via: :get
        #
        #         class PermitList
        #           def matches?(request) request.remote_ip == '1.2.3.4' end
        #         end
        #         match 'path', to: 'c#a', constraints: PermitList.new, via: :get
        #
        #     See `Scoping#constraints` for more examples with its scope equivalent.
        #
        # :defaults
        # :   Sets defaults for parameters
        #
        #         # Sets params[:format] to 'jpg' by default
        #         match 'path', to: 'c#a', defaults: { format: 'jpg' }, via: :get
        #
        #     See `Scoping#defaults` for its scope equivalent.
        #
        # :anchor
        # :   Boolean to anchor a `match` pattern. Default is true. When set to false,
        #     the pattern matches any request prefixed with the given path.
        #
        #         # Matches any request starting with 'path'
        #         match 'path', to: 'c#a', anchor: false, via: :get
        #
        # :format
        # :   Allows you to specify the default value for optional `format` segment or
        #     disable it by supplying `false`.
        #
        def match(path, options = nil)
        end

        # Mount a Rack-based application to be used within the application.
        #
        #     mount SomeRackApp, at: "some_route"
        #
        # For options, see `match`, as `mount` uses it internally.
        #
        # All mounted applications come with routing helpers to access them. These are
        # named after the class specified, so for the above example the helper is either
        # `some_rack_app_path` or `some_rack_app_url`. To customize this helper's name,
        # use the `:as` option:
        #
        #     mount(SomeRackApp, at: "some_route", as: "exciting")
        #
        # This will generate the `exciting_path` and `exciting_url` helpers which can be
        # used to navigate to this mounted app.
        def mount(app = nil, deprecated_options = nil, as: DEFAULT, via: nil, at: nil, defaults: nil, constraints: nil, anchor: false, format: false, path: nil, internal: nil, **mapping, &block)
          if deprecated_options.is_a?(Hash)
            as = assign_deprecated_option(deprecated_options, :as, :mount) if deprecated_options.key?(:as)
            via ||= assign_deprecated_option(deprecated_options, :via, :mount)
            at ||= assign_deprecated_option(deprecated_options, :at, :mount)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :mount)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :mount)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :mount) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :mount) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :mount)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :mount)
            assign_deprecated_options(deprecated_options, mapping, :mount)
          end

          path_or_action = at

          if app.nil?
            hash_app, hash_path = mapping.find { |key, _| key.respond_to?(:call) }
            mapping.delete(hash_app) if hash_app

            app ||= hash_app
            path_or_action ||= hash_path
          end

          raise ArgumentError, "A rack application must be specified" unless app.respond_to?(:call)
          raise ArgumentError, <<~MSG unless path_or_action
            Must be called with mount point

              mount SomeRackApp, at: "some_route"
              or
              mount(SomeRackApp => "some_route")
          MSG

          rails_app = rails_app? app
          as = app_name(app, rails_app) if as == DEFAULT

          target_as = name_for_action(as, path_or_action)
          via ||= :all

          match(path_or_action, to: app, as:, via:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, &block)

          define_generate_prefix(app, target_as) if rails_app
          self
        end

        def default_url_options=(options)
          @set.default_url_options = options
        end
        alias_method :default_url_options, :default_url_options=

        def with_default_scope(scope, &block)
          scope(**scope) do
            instance_exec(&block)
          end
        end

        # Query if the following named route was already defined.
        def has_named_route?(name)
          @set.named_routes.key?(name)
        end

        private
          def assign_deprecated_option(deprecated_options, key, method_name)
            if (deprecated_value = deprecated_options.delete(key))
              ActionDispatch.deprecator.warn(<<~MSG.squish)
                #{method_name} received a hash argument #{key}. Please use a keyword instead. Support to hash argument will be removed in Rails 8.2.
              MSG
              deprecated_value
            end
          end

          def assign_deprecated_options(deprecated_options, options, method_name)
            deprecated_options.each do |key, value|
              ActionDispatch.deprecator.warn(<<~MSG.squish)
                #{method_name} received a hash argument #{key}. Please use a keyword instead. Support to hash argument will be removed in Rails 8.2.
              MSG
              options[key] = value
            end
          end

          def rails_app?(app)
            app.is_a?(Class) && app < Rails::Railtie
          end

          def app_name(app, rails_app)
            if rails_app
              app.railtie_name
            elsif app.is_a?(Class)
              class_name = app.name
              ActiveSupport::Inflector.underscore(class_name).tr("/", "_")
            end
          end

          def define_generate_prefix(app, name)
            _route = @set.named_routes.get name
            _routes = @set
            _url_helpers = @set.url_helpers

            script_namer = ->(options) do
              prefix_options = options.slice(*_route.segment_keys)
              prefix_options[:script_name] = "" if options[:original_script_name]

              if options[:_recall]
                prefix_options.reverse_merge!(options[:_recall].slice(*_route.segment_keys))
              end

              # We must actually delete prefix segment keys to avoid passing them to next
              # url_for.
              _route.segment_keys.each { |k| options.delete(k) }
              _url_helpers.public_send("#{name}_path", prefix_options)
            end

            app.routes.define_mounted_helper(name, script_namer)

            app.routes.extend Module.new {
              def optimize_routes_generation?; false; end

              define_method :find_script_name do |options|
                if options.key?(:script_name) && options[:script_name].present?
                  super(options)
                else
                  script_namer.call(options)
                end
              end
            }
          end
      end

      module HttpHelpers
        # Define a route that only recognizes HTTP GET. For supported arguments, see
        # [match](rdoc-ref:Base#match)
        #
        #     get 'bacon', to: 'food#bacon'
        def get(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: nil, format: nil, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :get) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :get)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :get)
            action ||= assign_deprecated_option(deprecated_options, :action, :get)
            on ||= assign_deprecated_option(deprecated_options, :on, :get)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :get)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :get)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :get) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :get) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :get)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :get)
            assign_deprecated_options(deprecated_options, mapping, :get)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: :get, &block)
          self
        end

        # Define a route that only recognizes HTTP POST. For supported arguments, see
        # [match](rdoc-ref:Base#match)
        #
        #     post 'bacon', to: 'food#bacon'
        def post(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: nil, format: nil, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :post) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :post)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :post)
            action ||= assign_deprecated_option(deprecated_options, :action, :post)
            on ||= assign_deprecated_option(deprecated_options, :on, :post)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :post)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :post)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :post) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :post) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :post)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :post)
            assign_deprecated_options(deprecated_options, mapping, :post)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: :post, &block)
          self
        end

        # Define a route that only recognizes HTTP PATCH. For supported arguments, see
        # [match](rdoc-ref:Base#match)
        #
        #     patch 'bacon', to: 'food#bacon'
        def patch(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: nil, format: nil, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :patch) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :patch)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :patch)
            action ||= assign_deprecated_option(deprecated_options, :action, :patch)
            on ||= assign_deprecated_option(deprecated_options, :on, :patch)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :patch)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :patch)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :patch) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :patch) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :patch)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :patch)
            assign_deprecated_options(deprecated_options, mapping, :patch)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: :patch, &block)
          self
        end

        # Define a route that only recognizes HTTP PUT. For supported arguments, see
        # [match](rdoc-ref:Base#match)
        #
        #     put 'bacon', to: 'food#bacon'
        def put(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: nil, format: nil, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :put) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :put)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :put)
            action ||= assign_deprecated_option(deprecated_options, :action, :put)
            on ||= assign_deprecated_option(deprecated_options, :on, :put)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :put)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :put)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :put) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :put) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :put)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :put)
            assign_deprecated_options(deprecated_options, mapping, :put)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: :put, &block)
          self
        end

        # Define a route that only recognizes HTTP DELETE. For supported arguments, see
        # [match](rdoc-ref:Base#match)
        #
        #     delete 'broccoli', to: 'food#broccoli'
        def delete(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: nil, format: nil, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :delete) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :delete)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :delete)
            action ||= assign_deprecated_option(deprecated_options, :action, :delete)
            on ||= assign_deprecated_option(deprecated_options, :on, :delete)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :delete)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :delete)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :delete) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :delete) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :delete)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :delete)
            assign_deprecated_options(deprecated_options, mapping, :delete)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: :delete, &block)
          self
        end

        # Define a route that only recognizes HTTP OPTIONS. For supported arguments, see
        # [match](rdoc-ref:Base#match)
        #
        #     options 'carrots', to: 'food#carrots'
        def options(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: false, format: false, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :options) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :options)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :options)
            action ||= assign_deprecated_option(deprecated_options, :action, :options)
            on ||= assign_deprecated_option(deprecated_options, :on, :options)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :options)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :options)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :options) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :options) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :options)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :options)
            assign_deprecated_options(deprecated_options, mapping, :options)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: :options, &block)
          self
        end

        # Define a route that recognizes HTTP CONNECT (and GET) requests. More
        # specifically this recognizes HTTP/1 protocol upgrade requests and HTTP/2
        # CONNECT requests with the protocol pseudo header. For supported arguments,
        # see [match](rdoc-ref:Base#match)
        #
        #     connect 'live', to: 'live#index'
        def connect(*path_or_actions, as: DEFAULT, to: nil, controller: nil, action: nil, on: nil, defaults: nil, constraints: nil, anchor: false, format: false, path: nil, internal: nil, **mapping, &block)
          if path_or_actions.grep(Hash).any? && (deprecated_options = path_or_actions.extract_options!)
            as = assign_deprecated_option(deprecated_options, :as, :connect) if deprecated_options.key?(:as)
            to ||= assign_deprecated_option(deprecated_options, :to, :connect)
            controller ||= assign_deprecated_option(deprecated_options, :controller, :connect)
            action ||= assign_deprecated_option(deprecated_options, :action, :connect)
            on ||= assign_deprecated_option(deprecated_options, :on, :connect)
            defaults ||= assign_deprecated_option(deprecated_options, :defaults, :connect)
            constraints ||= assign_deprecated_option(deprecated_options, :constraints, :connect)
            anchor = assign_deprecated_option(deprecated_options, :anchor, :connect) if deprecated_options.key?(:anchor)
            format = assign_deprecated_option(deprecated_options, :format, :connect) if deprecated_options.key?(:format)
            path ||= assign_deprecated_option(deprecated_options, :path, :connect)
            internal ||= assign_deprecated_option(deprecated_options, :internal, :connect)
            assign_deprecated_options(deprecated_options, mapping, :connect)
          end

          match(*path_or_actions, as:, to:, controller:, action:, on:, defaults:, constraints:, anchor:, format:, path:, internal:, **mapping, via: [:get, :connect], &block)
          self
        end
      end

      # You may wish to organize groups of controllers under a namespace. Most
      # commonly, you might group a number of administrative controllers under an
      # `admin` namespace. You would place these controllers under the
      # `app/controllers/admin` directory, and you can group them together in your
      # router:
      #
      #     namespace "admin" do
      #       resources :posts, :comments
      #     end
      #
      # This will create a number of routes for each of the posts and comments
      # controller. For `Admin::PostsController`, Rails will create:
      #
      #     GET       /admin/posts
      #     GET       /admin/posts/new
      #     POST      /admin/posts
      #     GET       /admin/posts/1
      #     GET       /admin/posts/1/edit
      #     PATCH/PUT /admin/posts/1
      #     DELETE    /admin/posts/1
      #
      # If you want to route /posts (without the prefix /admin) to
      # `Admin::PostsController`, you could use
      #
      #     scope module: "admin" do
      #       resources :posts
      #     end
      #
      # or, for a single case
      #
      #     resources :posts, module: "admin"
      #
      # If you want to route /admin/posts to `PostsController` (without the `Admin::`
      # module prefix), you could use
      #
      #     scope "/admin" do
      #       resources :posts
      #     end
      #
      # or, for a single case
      #
      #     resources :posts, path: "/admin/posts"
      #
      # In each of these cases, the named routes remain the same as if you did not use
      # scope. In the last case, the following paths map to `PostsController`:
      #
      #     GET       /admin/posts
      #     GET       /admin/posts/new
      #     POST      /admin/posts
      #     GET       /admin/posts/1
      #     GET       /admin/posts/1/edit
      #     PATCH/PUT /admin/posts/1
      #     DELETE    /admin/posts/1
      module Scoping
        # Scopes a set of routes to the given default options.
        #
        # Take the following route definition as an example:
        #
        #     scope path: ":account_id", as: "account" do
        #       resources :projects
        #     end
        #
        # This generates helpers such as `account_projects_path`, just like `resources`
        # does. The difference here being that the routes generated are like
        # /:account_id/projects, rather than /accounts/:account_id/projects.
        #
        # ### Options
        #
        # Takes same options as `Base#match` and `Resources#resources`.
        #
        #     # route /posts (without the prefix /admin) to Admin::PostsController
        #     scope module: "admin" do
        #       resources :posts
        #     end
        #
        #     # prefix the posts resource's requests with '/admin'
        #     scope path: "/admin" do
        #       resources :posts
        #     end
        #
        #     # prefix the routing helper name: sekret_posts_path instead of posts_path
        #     scope as: "sekret" do
        #       resources :posts
        #     end
        def scope(*args, only: nil, except: nil, **options)
          if args.grep(Hash).any? && (deprecated_options = args.extract_options!)
            only ||= assign_deprecated_option(deprecated_options, :only, :scope)
            only ||= assign_deprecated_option(deprecated_options, :except, :scope)
            assign_deprecated_options(deprecated_options, options, :scope)
          end

          scope = {}

          options[:path] = args.flatten.join("/") if args.any?
          options[:constraints] ||= {}

          unless nested_scope?
            options[:shallow_path] ||= options[:path] if options.key?(:path)
            options[:shallow_prefix] ||= options[:as] if options.key?(:as)
          end

          if options[:constraints].is_a?(Hash)
            defaults = options[:constraints].select do |k, v|
              URL_OPTIONS.include?(k) && (v.is_a?(String) || v.is_a?(Integer))
            end

            options[:defaults] = defaults.merge(options[:defaults] || {})
          else
            block, options[:constraints] = options[:constraints], {}
          end

          if only || except
            scope[:action_options] = { only:, except: }
          end

          if options.key? :anchor
            raise ArgumentError, "anchor is ignored unless passed to `match`"
          end

          @scope.options.each do |option|
            if option == :blocks
              value = block
            elsif option == :options
              value = options
            else
              value = options.delete(option) { POISON }
            end

            unless POISON == value
              scope[option] = send("merge_#{option}_scope", @scope[option], value)
            end
          end

          @scope = @scope.new scope
          yield
          self
        ensure
          @scope = @scope.parent
        end

        POISON = Object.new # :nodoc:

        # Scopes routes to a specific controller
        #
        #     controller "food" do
        #       match "bacon", action: :bacon, via: :get
        #     end
        def controller(controller)
          @scope = @scope.new(controller: controller)
          yield
        ensure
          @scope = @scope.parent
        end

        # Scopes routes to a specific namespace. For example:
        #
        #     namespace :admin do
        #       resources :posts
        #     end
        #
        # This generates the following routes:
        #
        #         admin_posts GET       /admin/posts(.:format)          admin/posts#index
        #         admin_posts POST      /admin/posts(.:format)          admin/posts#create
        #      new_admin_post GET       /admin/posts/new(.:format)      admin/posts#new
        #     edit_admin_post GET       /admin/posts/:id/edit(.:format) admin/posts#edit
        #          admin_post GET       /admin/posts/:id(.:format)      admin/posts#show
        #          admin_post PATCH/PUT /admin/posts/:id(.:format)      admin/posts#update
        #          admin_post DELETE    /admin/posts/:id(.:format)      admin/posts#destroy
        #
        # ### Options
        #
        # The `:path`, `:as`, `:module`, `:shallow_path`, and `:shallow_prefix` options
        # all default to the name of the namespace.
        #
        # For options, see `Base#match`. For `:shallow_path` option, see
        # `Resources#resources`.
        #
        #     # accessible through /sekret/posts rather than /admin/posts
        #     namespace :admin, path: "sekret" do
        #       resources :posts
        #     end
        #
        #     # maps to Sekret::PostsController rather than Admin::PostsController
        #     namespace :admin, module: "sekret" do
        #       resources :posts
        #     end
        #
        #     # generates sekret_posts_path rather than admin_posts_path
        #     namespace :admin, as: "sekret" do
        #       resources :posts
        #     end
        def namespace(name, deprecated_options = nil, as: DEFAULT, path: DEFAULT, shallow_path: DEFAULT, shallow_prefix: DEFAULT, **options, &block)
          if deprecated_options.is_a?(Hash)
            as = assign_deprecated_option(deprecated_options, :as, :namespace) if deprecated_options.key?(:as)
            path ||= assign_deprecated_option(deprecated_options, :path, :namespace)  if deprecated_options.key?(:path)
            shallow_path ||= assign_deprecated_option(deprecated_options, :shallow_path, :namespace) if deprecated_options.key?(:shallow_path)
            shallow_prefix ||= assign_deprecated_option(deprecated_options, :shallow_prefix, :namespace)  if deprecated_options.key?(:shallow_prefix)
            assign_deprecated_options(deprecated_options, options, :namespace)
          end

          name = name.to_s
          options[:module] ||= name
          as = name if as == DEFAULT
          path = name if path == DEFAULT
          shallow_path = path if shallow_path == DEFAULT
          shallow_prefix = as if shallow_prefix == DEFAULT

          path_scope(path) do
            scope(**options, as:, shallow_path:, shallow_prefix:, &block)
          end
        end

        # ### Parameter Restriction
        # Allows you to constrain the nested routes based on a set of rules. For
        # instance, in order to change the routes to allow for a dot character in the
        # `id` parameter:
        #
        #     constraints(id: /\d+\.\d+/) do
        #       resources :posts
        #     end
        #
        # Now routes such as `/posts/1` will no longer be valid, but `/posts/1.1` will
        # be. The `id` parameter must match the constraint passed in for this example.
