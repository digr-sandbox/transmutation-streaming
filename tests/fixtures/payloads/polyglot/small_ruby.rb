# frozen_string_literal: true

# :markup: markdown

module ActionDispatch
  # The routing module provides URL rewriting in native Ruby. It's a way to
  # redirect incoming requests to controllers and actions. This replaces
  # mod_rewrite rules. Best of all, Rails' Routing works with any web server.
  # Routes are defined in `config/routes.rb`.
  #
  # Think of creating routes as drawing a map for your requests. The map tells
  # them where to go based on some predefined pattern:
  #
  #     Rails.application.routes.draw do
  #       Pattern 1 tells some request to go to one place
  #       Pattern 2 tell them to go to another
  #       ...
  #     end
  #
  # The following symbols are special:
  #
  #     :controller maps to your controller name
  #     :action     maps to an action with your controllers
  #
  # Other names simply map to a parameter as in the case of `:id`.
  #
  # ## Resources
  #
  # Resource routing allows you to quickly declare all of the common routes for a
  # g
