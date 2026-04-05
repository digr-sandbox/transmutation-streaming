<?php
/**
 * Core Post API
 *
 * @package WordPress
 * @subpackage Post
 */

//
// Post Type registration.
//

/**
 * Creates the initial post types when 'init' action is fired.
 *
 * See {@see 'init'}.
 *
 * @since 2.9.0
 */
function create_initial_post_types() {
	WP_Post_Type::reset_default_labels();

	register_post_type(
		'post',
		array(
			'labels'                => array(
				'name_admin_bar' => _x( 'Post', 'add new from admin bar' ),
			),
			'public'                => true,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'            => 'post.php?post=%d', /* internal use only. don't use this when registering your own post type. */
			'capability_type'       => 'post',
			'map_meta_cap'          => true,
			'menu_position'         => 5,
			'menu_icon'             => 'dashicons-admin-post',
			'hierarchical'          => false,
			'rewrite'               => false,
			'query_var'             => false,
			'delete_with_user'      => true,
			'supports'              => array(
				'title',
				'editor' => array( 'notes' => true ),
				'author',
				'thumbnail',
				'excerpt',
				'trackbacks',
				'custom-fields',
				'comments',
				'revisions',
				'post-formats',
			),
			'show_in_rest'          => true,
			'rest_base'             => 'posts',
			'rest_controller_class' => 'WP_REST_Posts_Controller',
		)
	);

	register_post_type(
		'page',
		array(
			'labels'                => array(
				'name_admin_bar' => _x( 'Page', 'add new from admin bar' ),
			),
			'public'                => true,
			'publicly_queryable'    => false,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'            => 'post.php?post=%d', /* internal use only. don't use this when registering your own post type. */
			'capability_type'       => 'page',
			'map_meta_cap'          => true,
			'menu_position'         => 20,
			'menu_icon'             => 'dashicons-admin-page',
			'hierarchical'          => true,
			'rewrite'               => false,
			'query_var'             => false,
			'delete_with_user'      => true,
			'supports'              => array(
				'title',
				'editor' => array( 'notes' => true ),
				'author',
				'thumbnail',
				'page-attributes',
				'custom-fields',
				'comments',
				'revisions',
			),
			'show_in_rest'          => true,
			'rest_base'             => 'pages',
			'rest_controller_class' => 'WP_REST_Posts_Controller',
		)
	);

	register_post_type(
		'attachment',
		array(
			'labels'                => array(
				'name'           => _x( 'Media', 'post type general name' ),
				'name_admin_bar' => _x( 'Media', 'add new from admin bar' ),
				'add_new'        => __( 'Add Media File' ),
				'add_new_item'   => __( 'Add Media File' ),
				'edit_item'      => __( 'Edit Media' ),
				'view_item'      => ( '1' === get_option( 'wp_attachment_pages_enabled' ) ) ? __( 'View Attachment Page' ) : __( 'View Media File' ),
				'attributes'     => __( 'Attachment Attributes' ),
			),
			'public'                => true,
			'show_ui'               => true,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'            => 'post.php?post=%d', /* internal use only. don't use this when registering your own post type. */
			'capability_type'       => 'post',
			'capabilities'          => array(
				'create_posts' => 'upload_files',
			),
			'map_meta_cap'          => true,
			'menu_icon'             => 'dashicons-admin-media',
			'hierarchical'          => false,
			'rewrite'               => false,
			'query_var'             => false,
			'show_in_nav_menus'     => false,
			'delete_with_user'      => true,
			'supports'              => array( 'title', 'author', 'comments' ),
			'show_in_rest'          => true,
			'rest_base'             => 'media',
			'rest_controller_class' => 'WP_REST_Attachments_Controller',
		)
	);
	add_post_type_support( 'attachment:audio', 'thumbnail' );
	add_post_type_support( 'attachment:video', 'thumbnail' );

	register_post_type(
		'revision',
		array(
			'labels'           => array(
				'name'          => __( 'Revisions' ),
				'singular_name' => __( 'Revision' ),
			),
			'public'           => false,
			'_builtin'         => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'       => 'revision.php?revision=%d', /* internal use only. don't use this when registering your own post type. */
			'capability_type'  => 'post',
			'map_meta_cap'     => true,
			'hierarchical'     => false,
			'rewrite'          => false,
			'query_var'        => false,
			'can_export'       => false,
			'delete_with_user' => true,
			'supports'         => array( 'author' ),
		)
	);

	register_post_type(
		'nav_menu_item',
		array(
			'labels'                => array(
				'name'          => __( 'Navigation Menu Items' ),
				'singular_name' => __( 'Navigation Menu Item' ),
			),
			'public'                => false,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'hierarchical'          => false,
			'rewrite'               => false,
			'delete_with_user'      => false,
			'query_var'             => false,
			'map_meta_cap'          => true,
			'capability_type'       => array( 'edit_theme_options', 'edit_theme_options' ),
			'capabilities'          => array(
				// Meta Capabilities.
				'edit_post'              => 'edit_post',
				'read_post'              => 'read_post',
				'delete_post'            => 'delete_post',
				// Primitive Capabilities.
				'edit_posts'             => 'edit_theme_options',
				'edit_others_posts'      => 'edit_theme_options',
				'delete_posts'           => 'edit_theme_options',
				'publish_posts'          => 'edit_theme_options',
				'read_private_posts'     => 'edit_theme_options',
				'read'                   => 'read',
				'delete_private_posts'   => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'edit_private_posts'     => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
			),
			'show_in_rest'          => true,
			'rest_base'             => 'menu-items',
			'rest_controller_class' => 'WP_REST_Menu_Items_Controller',
		)
	);

	register_post_type(
		'custom_css',
		array(
			'labels'           => array(
				'name'          => __( 'Custom CSS' ),
				'singular_name' => __( 'Custom CSS' ),
			),
			'public'           => false,
			'hierarchical'     => false,
			'rewrite'          => false,
			'query_var'        => false,
			'delete_with_user' => false,
			'can_export'       => true,
			'_builtin'         => true, /* internal use only. don't use this when registering your own post type. */
			'supports'         => array( 'title', 'revisions' ),
			'capabilities'     => array(
				'delete_posts'           => 'edit_theme_options',
				'delete_post'            => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
				'delete_private_posts'   => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'edit_post'              => 'edit_css',
				'edit_posts'             => 'edit_css',
				'edit_others_posts'      => 'edit_css',
				'edit_published_posts'   => 'edit_css',
				'read_post'              => 'read',
				'read_private_posts'     => 'read',
				'publish_posts'          => 'edit_theme_options',
			),
		)
	);

	register_post_type(
		'customize_changeset',
		array(
			'labels'           => array(
				'name'               => _x( 'Changesets', 'post type general name' ),
				'singular_name'      => _x( 'Changeset', 'post type singular name' ),
				'add_new'            => __( 'Add Changeset' ),
				'add_new_item'       => __( 'Add Changeset' ),
				'new_item'           => __( 'New Changeset' ),
				'edit_item'          => __( 'Edit Changeset' ),
				'view_item'          => __( 'View Changeset' ),
				'all_items'          => __( 'All Changesets' ),
				'search_items'       => __( 'Search Changesets' ),
				'not_found'          => __( 'No changesets found.' ),
				'not_found_in_trash' => __( 'No changesets found in Trash.' ),
			),
			'public'           => false,
			'_builtin'         => true, /* internal use only. don't use this when registering your own post type. */
			'map_meta_cap'     => true,
			'hierarchical'     => false,
			'rewrite'          => false,
			'query_var'        => false,
			'can_export'       => false,
			'delete_with_user' => false,
			'supports'         => array( 'title', 'author' ),
			'capability_type'  => 'customize_changeset',
			'capabilities'     => array(
				'create_posts'           => 'customize',
				'delete_others_posts'    => 'customize',
				'delete_post'            => 'customize',
				'delete_posts'           => 'customize',
				'delete_private_posts'   => 'customize',
				'delete_published_posts' => 'customize',
				'edit_others_posts'      => 'customize',
				'edit_post'              => 'customize',
				'edit_posts'             => 'customize',
				'edit_private_posts'     => 'customize',
				'edit_published_posts'   => 'do_not_allow',
				'publish_posts'          => 'customize',
				'read'                   => 'read',
				'read_post'              => 'customize',
				'read_private_posts'     => 'customize',
			),
		)
	);

	register_post_type(
		'oembed_cache',
		array(
			'labels'           => array(
				'name'          => __( 'oEmbed Responses' ),
				'singular_name' => __( 'oEmbed Response' ),
			),
			'public'           => false,
			'hierarchical'     => false,
			'rewrite'          => false,
			'query_var'        => false,
			'delete_with_user' => false,
			'can_export'       => false,
			'_builtin'         => true, /* internal use only. don't use this when registering your own post type. */
			'supports'         => array(),
		)
	);

	register_post_type(
		'user_request',
		array(
			'labels'           => array(
				'name'          => __( 'User Requests' ),
				'singular_name' => __( 'User Request' ),
			),
			'public'           => false,
			'_builtin'         => true, /* internal use only. don't use this when registering your own post type. */
			'hierarchical'     => false,
			'rewrite'          => false,
			'query_var'        => false,
			'can_export'       => false,
			'delete_with_user' => false,
			'supports'         => array(),
		)
	);

	register_post_type(
		'wp_block',
		array(
			'labels'                => array(
				'name'                     => _x( 'Patterns', 'post type general name' ),
				'singular_name'            => _x( 'Pattern', 'post type singular name' ),
				'add_new'                  => __( 'Add Pattern' ),
				'add_new_item'             => __( 'Add Pattern' ),
				'new_item'                 => __( 'New Pattern' ),
				'edit_item'                => __( 'Edit Block Pattern' ),
				'view_item'                => __( 'View Pattern' ),
				'view_items'               => __( 'View Patterns' ),
				'all_items'                => __( 'All Patterns' ),
				'search_items'             => __( 'Search Patterns' ),
				'not_found'                => __( 'No patterns found.' ),
				'not_found_in_trash'       => __( 'No patterns found in Trash.' ),
				'filter_items_list'        => __( 'Filter patterns list' ),
				'items_list_navigation'    => __( 'Patterns list navigation' ),
				'items_list'               => __( 'Patterns list' ),
				'item_published'           => __( 'Pattern published.' ),
				'item_published_privately' => __( 'Pattern published privately.' ),
				'item_reverted_to_draft'   => __( 'Pattern reverted to draft.' ),
				'item_scheduled'           => __( 'Pattern scheduled.' ),
				'item_updated'             => __( 'Pattern updated.' ),
			),
			'public'                => false,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'show_ui'               => true,
			'show_in_menu'          => false,
			'rewrite'               => false,
			'show_in_rest'          => true,
			'rest_base'             => 'blocks',
			'rest_controller_class' => 'WP_REST_Blocks_Controller',
			'capability_type'       => 'block',
			'capabilities'          => array(
				// You need to be able to edit posts, in order to read blocks in their raw form.
				'read'                   => 'edit_posts',
				// You need to be able to publish posts, in order to create blocks.
				'create_posts'           => 'publish_posts',
				'edit_posts'             => 'edit_posts',
				'edit_published_posts'   => 'edit_published_posts',
				'delete_published_posts' => 'delete_published_posts',
				// Enables trashing draft posts as well.
				'delete_posts'           => 'delete_posts',
				'edit_others_posts'      => 'edit_others_posts',
				'delete_others_posts'    => 'delete_others_posts',
			),
			'map_meta_cap'          => true,
			'supports'              => array(
				'title',
				'excerpt',
				'editor',
				'revisions',
				'custom-fields',
			),
		)
	);

	$template_edit_link = 'site-editor.php?' . build_query(
		array(
			'p'      => '/%s/%s',
			'canvas' => 'edit',
		)
	);

	register_post_type(
		'wp_template',
		array(
			'labels'                          => array(
				'name'                  => _x( 'Templates', 'post type general name' ),
				'singular_name'         => _x( 'Template', 'post type singular name' ),
				'add_new'               => __( 'Add Template' ),
				'add_new_item'          => __( 'Add Template' ),
				'new_item'              => __( 'New Template' ),
				'edit_item'             => __( 'Edit Template' ),
				'view_item'             => __( 'View Template' ),
				'all_items'             => __( 'Templates' ),
				'search_items'          => __( 'Search Templates' ),
				'parent_item_colon'     => __( 'Parent Template:' ),
				'not_found'             => __( 'No templates found.' ),
				'not_found_in_trash'    => __( 'No templates found in Trash.' ),
				'archives'              => __( 'Template archives' ),
				'insert_into_item'      => __( 'Insert into template' ),
				'uploaded_to_this_item' => __( 'Uploaded to this template' ),
				'filter_items_list'     => __( 'Filter templates list' ),
				'items_list_navigation' => __( 'Templates list navigation' ),
				'items_list'            => __( 'Templates list' ),
				'item_updated'          => __( 'Template updated.' ),
			),
			'description'                     => __( 'Templates to include in your theme.' ),
			'public'                          => false,
			'_builtin'                        => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'                      => $template_edit_link, /* internal use only. don't use this when registering your own post type. */
			'has_archive'                     => false,
			'show_ui'                         => false,
			'show_in_menu'                    => false,
			'show_in_rest'                    => true,
			'rewrite'                         => false,
			'rest_base'                       => 'templates',
			'rest_controller_class'           => 'WP_REST_Templates_Controller',
			'autosave_rest_controller_class'  => 'WP_REST_Template_Autosaves_Controller',
			'revisions_rest_controller_class' => 'WP_REST_Template_Revisions_Controller',
			'late_route_registration'         => true,
			'capability_type'                 => array( 'template', 'templates' ),
			'capabilities'                    => array(
				'create_posts'           => 'edit_theme_options',
				'delete_posts'           => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'delete_private_posts'   => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
				'edit_posts'             => 'edit_theme_options',
				'edit_others_posts'      => 'edit_theme_options',
				'edit_private_posts'     => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
				'publish_posts'          => 'edit_theme_options',
				'read'                   => 'edit_theme_options',
				'read_private_posts'     => 'edit_theme_options',
			),
			'map_meta_cap'                    => true,
			'supports'                        => array(
				'title',
				'slug',
				'excerpt',
				'editor',
				'revisions',
				'author',
			),
		)
	);

	register_post_type(
		'wp_template_part',
		array(
			'labels'                          => array(
				'name'                  => _x( 'Template Parts', 'post type general name' ),
				'singular_name'         => _x( 'Template Part', 'post type singular name' ),
				'add_new'               => __( 'Add Template Part' ),
				'add_new_item'          => __( 'Add Template Part' ),
				'new_item'              => __( 'New Template Part' ),
				'edit_item'             => __( 'Edit Template Part' ),
				'view_item'             => __( 'View Template Part' ),
				'all_items'             => __( 'Template Parts' ),
				'search_items'          => __( 'Search Template Parts' ),
				'parent_item_colon'     => __( 'Parent Template Part:' ),
				'not_found'             => __( 'No template parts found.' ),
				'not_found_in_trash'    => __( 'No template parts found in Trash.' ),
				'archives'              => __( 'Template part archives' ),
				'insert_into_item'      => __( 'Insert into template part' ),
				'uploaded_to_this_item' => __( 'Uploaded to this template part' ),
				'filter_items_list'     => __( 'Filter template parts list' ),
				'items_list_navigation' => __( 'Template parts list navigation' ),
				'items_list'            => __( 'Template parts list' ),
				'item_updated'          => __( 'Template part updated.' ),
			),
			'description'                     => __( 'Template parts to include in your templates.' ),
			'public'                          => false,
			'_builtin'                        => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'                      => $template_edit_link, /* internal use only. don't use this when registering your own post type. */
			'has_archive'                     => false,
			'show_ui'                         => false,
			'show_in_menu'                    => false,
			'show_in_rest'                    => true,
			'rewrite'                         => false,
			'rest_base'                       => 'template-parts',
			'rest_controller_class'           => 'WP_REST_Templates_Controller',
			'autosave_rest_controller_class'  => 'WP_REST_Template_Autosaves_Controller',
			'revisions_rest_controller_class' => 'WP_REST_Template_Revisions_Controller',
			'late_route_registration'         => true,
			'map_meta_cap'                    => true,
			'capabilities'                    => array(
				'create_posts'           => 'edit_theme_options',
				'delete_posts'           => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'delete_private_posts'   => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
				'edit_posts'             => 'edit_theme_options',
				'edit_others_posts'      => 'edit_theme_options',
				'edit_private_posts'     => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
				'publish_posts'          => 'edit_theme_options',
				'read'                   => 'edit_theme_options',
				'read_private_posts'     => 'edit_theme_options',
			),
			'supports'                        => array(
				'title',
				'slug',
				'excerpt',
				'editor',
				'revisions',
				'author',
			),
		)
	);

	register_post_type(
		'wp_global_styles',
		array(
			'label'                           => _x( 'Global Styles', 'post type general name' ),
			'description'                     => __( 'Global styles to include in themes.' ),
			'public'                          => false,
			'_builtin'                        => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'                      => '/site-editor.php?canvas=edit', /* internal use only. don't use this when registering your own post type. */
			'show_ui'                         => false,
			'show_in_rest'                    => true,
			'rewrite'                         => false,
			'rest_base'                       => 'global-styles',
			'rest_controller_class'           => 'WP_REST_Global_Styles_Controller',
			'revisions_rest_controller_class' => 'WP_REST_Global_Styles_Revisions_Controller',
			'late_route_registration'         => true,
			'capabilities'                    => array(
				'read'                   => 'edit_posts',
				'create_posts'           => 'edit_theme_options',
				'edit_posts'             => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
				'edit_others_posts'      => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
			),
			'map_meta_cap'                    => true,
			'supports'                        => array(
				'title',
				'editor',
				'revisions',
			),
		)
	);
	// Disable autosave endpoints for global styles.
	remove_post_type_support( 'wp_global_styles', 'autosave' );

	$navigation_post_edit_link = 'site-editor.php?' . build_query(
		array(
			'p'      => '/wp_navigation/%s',
			'canvas' => 'edit',
		)
	);

	register_post_type(
		'wp_navigation',
		array(
			'labels'                => array(
				'name'                  => _x( 'Navigation Menus', 'post type general name' ),
				'singular_name'         => _x( 'Navigation Menu', 'post type singular name' ),
				'add_new'               => __( 'Add Navigation Menu' ),
				'add_new_item'          => __( 'Add Navigation Menu' ),
				'new_item'              => __( 'New Navigation Menu' ),
				'edit_item'             => __( 'Edit Navigation Menu' ),
				'view_item'             => __( 'View Navigation Menu' ),
				'all_items'             => __( 'Navigation Menus' ),
				'search_items'          => __( 'Search Navigation Menus' ),
				'parent_item_colon'     => __( 'Parent Navigation Menu:' ),
				'not_found'             => __( 'No Navigation Menu found.' ),
				'not_found_in_trash'    => __( 'No Navigation Menu found in Trash.' ),
				'archives'              => __( 'Navigation Menu archives' ),
				'insert_into_item'      => __( 'Insert into Navigation Menu' ),
				'uploaded_to_this_item' => __( 'Uploaded to this Navigation Menu' ),
				'filter_items_list'     => __( 'Filter Navigation Menu list' ),
				'items_list_navigation' => __( 'Navigation Menus list navigation' ),
				'items_list'            => __( 'Navigation Menus list' ),
				'item_updated'          => __( 'Navigation Menu updated.' ),
			),
			'description'           => __( 'Navigation menus that can be inserted into your site.' ),
			'public'                => false,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'_edit_link'            => $navigation_post_edit_link, /* internal use only. don't use this when registering your own post type. */
			'has_archive'           => false,
			'show_ui'               => true,
			'show_in_menu'          => false,
			'show_in_admin_bar'     => false,
			'show_in_rest'          => true,
			'rewrite'               => false,
			'map_meta_cap'          => true,
			'capabilities'          => array(
				'edit_others_posts'      => 'edit_theme_options',
				'delete_posts'           => 'edit_theme_options',
				'publish_posts'          => 'edit_theme_options',
				'create_posts'           => 'edit_theme_options',
				'read_private_posts'     => 'edit_theme_options',
				'delete_private_posts'   => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'edit_private_posts'     => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
				'edit_posts'             => 'edit_theme_options',
			),
			'rest_base'             => 'navigation',
			'rest_controller_class' => 'WP_REST_Posts_Controller',
			'supports'              => array(
				'title',
				'editor',
				'revisions',
			),
		)
	);

	register_post_type(
		'wp_font_family',
		array(
			'labels'                => array(
				'name'          => __( 'Font Families' ),
				'singular_name' => __( 'Font Family' ),
			),
			'public'                => false,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'hierarchical'          => false,
			'capabilities'          => array(
				'read'                   => 'edit_theme_options',
				'read_private_posts'     => 'edit_theme_options',
				'create_posts'           => 'edit_theme_options',
				'publish_posts'          => 'edit_theme_options',
				'edit_posts'             => 'edit_theme_options',
				'edit_others_posts'      => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
				'delete_posts'           => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
			),
			'map_meta_cap'          => true,
			'query_var'             => false,
			'rewrite'               => false,
			'show_in_rest'          => true,
			'rest_base'             => 'font-families',
			'rest_controller_class' => 'WP_REST_Font_Families_Controller',
			'supports'              => array( 'title' ),
		)
	);

	register_post_type(
		'wp_font_face',
		array(
			'labels'                => array(
				'name'          => __( 'Font Faces' ),
				'singular_name' => __( 'Font Face' ),
			),
			'public'                => false,
			'_builtin'              => true, /* internal use only. don't use this when registering your own post type. */
			'hierarchical'          => false,
			'capabilities'          => array(
				'read'                   => 'edit_theme_options',
				'read_private_posts'     => 'edit_theme_options',
				'create_posts'           => 'edit_theme_options',
				'publish_posts'          => 'edit_theme_options',
				'edit_posts'             => 'edit_theme_options',
				'edit_others_posts'      => 'edit_theme_options',
				'edit_published_posts'   => 'edit_theme_options',
				'delete_posts'           => 'edit_theme_options',
				'delete_others_posts'    => 'edit_theme_options',
				'delete_published_posts' => 'edit_theme_options',
			),
			'map_meta_cap'          => true,
			'query_var'             => false,
			'rewrite'               => false,
			'show_in_rest'          => true,
			'rest_base'             => 'font-families/(?P<font_family_id>[\d]+)/font-faces',
			'rest_controller_class' => 'WP_REST_Font_Faces_Controller',
			'supports'              => array( 'title' ),
		)
	);

	if ( wp_is_collaboration_enabled() ) {
		register_post_type(
			'wp_sync_storage',
			array(
				'labels'             => array(
					'name'          => __( 'Sync Updates' ),
					'singular_name' => __( 'Sync Update' ),
				),
				'public'             => false,
				'_builtin'           => true, /* internal use only. don't use this when registering your own post type. */
				'hierarchical'       => false,
				'capabilities'       => array(
					'read'                   => 'do_not_allow',
					'read_private_posts'     => 'do_not_allow',
					'create_posts'           => 'do_not_allow',
					'publish_posts'          => 'do_not_allow',
					'edit_posts'             => 'do_not_allow',
					'edit_others_posts'      => 'do_not_allow',
					'edit_published_posts'   => 'do_not_allow',
					'delete_posts'           => 'do_not_allow',
					'delete_others_posts'    => 'do_not_allow',
					'delete_published_posts' => 'do_not_allow',
				),
				'map_meta_cap'       => false,
				'publicly_queryable' => false,
				'query_var'          => false,
				'rewrite'            => false,
				'show_in_menu'       => false,
				'show_in_rest'       => false,
				'show_ui'            => false,
				'can_export'         => false,
				'supports'           => array( 'custom-fields' ),
			)
		);
	}

	register_post_status(
		'publish',
		array(
			'label'       => _x( 'Published', 'post status' ),
			'public'      => true,
			'_builtin'    => true, /* internal use only. */
			/* translators: %s: Number of published posts. */
			'label_count' => _n_noop(
				'Published <span class="count">(%s)</span>',
				'Published <span class="count">(%s)</span>'
			),
		)
	);

	register_post_status(
		'future',
		array(
			'label'       => _x( 'Scheduled', 'post status' ),
			'protected'   => true,
			'_builtin'    => true, /* internal use only. */
			/* translators: %s: Number of scheduled posts. */
			'label_count' => _n_noop(
				'Scheduled <span class="count">(%s)</span>',
				'Scheduled <span class="count">(%s)</span>'
			),
		)
	);

	register_post_status(
		'draft',
		array(
			'label'         => _x( 'Draft', 'post status' ),
			'protected'     => true,
			'_builtin'      => true, /* internal use only. */
			/* translators: %s: Number of draft posts. */
			'label_count'   => _n_noop(
				'Draft <span class="count">(%s)</span>',
				'Drafts <span class="count">(%s)</span>'
			),
			'date_floating' => true,
		)
	);

	register_post_status(
		'pending',
		array(
			'label'         => _x( 'Pending', 'post status' ),
			'protected'     => true,
			'_builtin'      => true, /* internal use only. */
			/* translators: %s: Number of pending posts. */
			'label_count'   => _n_noop(
				'Pending <span class="count">(%s)</span>',
				'Pending <span class="count">(%s)</span>'
			),
			'date_floating' => true,
		)
	);

	register_post_status(
		'private',
		array(
			'label'       => _x( 'Private', 'post status' ),
			'private'     => true,
			'_builtin'    => true, /* internal use only. */
			/* translators: %s: Number of private posts. */
			'label_count' => _n_noop(
				'Private <span class="count">(%s)</span>',
				'Private <span class="count">(%s)</span>'
			),
		)
	);

	register_post_status(
		'trash',
		array(
			'label'                     => _x( 'Trash', 'post status' ),
			'internal'                  => true,
			'_builtin'                  => true, /* internal use only. */
			/* translators: %s: Number of trashed posts. */
			'label_count'               => _n_noop(
				'Trash <span class="count">(%s)</span>',
				'Trash <span class="count">(%s)</span>'
			),
			'show_in_admin_status_list' => true,
		)
	);

	register_post_status(
		'auto-draft',
		array(
			'label'         => 'auto-draft',
			'internal'      => true,
			'_builtin'      => true, /* internal use only. */
			'date_floating' => true,
		)
	);

	register_post_status(
		'inherit',
		array(
			'label'               => 'inherit',
			'internal'            => true,
			'_builtin'            => true, /* internal use only. */
			'exclude_from_search' => false,
		)
	);

	register_post_status(
		'request-pending',
		array(
			'label'               => _x( 'Pending', 'request status' ),
			'internal'            => true,
			'_builtin'            => true, /* internal use only. */
			/* translators: %s: Number of pending requests. */
			'label_count'         => _n_noop(
				'Pending <span class="count">(%s)</span>',
				'Pending <span class="count">(%s)</span>'
			),
			'exclude_from_search' => false,
		)
	);

	register_post_status(
		'request-confirmed',
		array(
			'label'               => _x( 'Confirmed', 'request status' ),
			'internal'            => true,
			'_builtin'            => true, /* internal use only. */
			/* translators: %s: Number of confirmed requests. */
			'label_count'         => _n_noop(
				'Confirmed <span class="count">(%s)</span>',
				'Confirmed <span class="count">(%s)</span>'
			),
			'exclude_from_search' => false,
		)
	);

	register_post_status(
		'request-failed',
		array(
			'label'               => _x( 'Failed', 'request status' ),
			'internal'            => true,
			'_builtin'            => true, /* internal use only. */
			/* translators: %s: Number of failed requests. */
			'label_count'         => _n_noop(
				'Failed <span class="count">(%s)</span>',
				'Failed <span class="count">(%s)</span>'
			),
			'exclude_from_search' => false,
		)
	);

	register_post_status(
		'request-completed',
		array(
			'label'               => _x( 'Completed', 'request status' ),
			'internal'            => true,
			'_builtin'            => true, /* internal use only. */
			/* translators: %s: Number of completed requests. */
			'label_count'         => _n_noop(
				'Completed <span class="count">(%s)</span>',
				'Completed <span class="count">(%s)</span>'
			),
			'exclude_from_search' => false,
		)
	);
}

/**
 * Retrieves attached file path based on attachment ID.
 *
 * By default the path will go through the {@see 'get_attached_file'} filter, but
 * passing `true` to the `$unfiltered` argument will return the file path unfiltered.
 *
 * The function works by retrieving the `_wp_attached_file` post meta value.
 * This is a convenience function to prevent looking up the meta name and provide
 * a mechanism for sending the attached filename through a filter.
 *
 * @since 2.0.0
 *
 * @param int  $attachment_id Attachment ID.
 * @param bool $unfiltered    Optional. Whether to skip the {@see 'get_attached_file'} filter.
 *                            Default false.
 * @return string|false The file path to where the attached file should be, false otherwise.
 */
function get_attached_file( $attachment_id, $unfiltered = false ) {
	$file = get_post_meta( $attachment_id, '_wp_attached_file', true );

	// If the file is relative, prepend upload dir.
	if ( $file && ! str_starts_with( $file, '/' ) && ! preg_match( '|^.:\\\|', $file ) ) {
		$uploads = wp_get_upload_dir();
		if ( false === $uploads['error'] ) {
			$file = $uploads['basedir'] . "/$file";
		}
	}

	if ( $unfiltered ) {
		return $file;
	}

	/**
	 * Filters the attached file based on the given ID.
	 *
	 * @since 2.1.0
	 *
	 * @param string|false $file          The file path to where the attached file should be, false otherwise.
	 * @param int          $attachment_id Attachment ID.
	 */
	return apply_filters( 'get_attached_file', $file, $attachment_id );
}

/**
 * Updates attachment file path based on attachment ID.
 *
 * Used to update the file path of the attachment, which uses post meta name
 * `_wp_attached_file` to store the path of the attachment.
 *
 * @since 2.1.0
 *
 * @param int    $attachment_id Attachment ID.
 * @param string $file          File path for the attachment.
 * @return int|bool Meta ID if the `_wp_attached_file` key didn't exist for the attachment.
 *                  True on successful update, false on failure or if the `$file` value passed
 *                  to the function is the same as the one that is already in the database.
 */
function update_attached_file( $attachment_id, $file ) {
	if ( ! get_post( $attachment_id ) ) {
		return false;
	}

	/**
	 * Filters the path to the attached file to update.
	 *
	 * @since 2.1.0
	 *
	 * @param string $file          Path to the attached file to update.
	 * @param int    $attachment_id Attachment ID.
	 */
	$file = apply_filters( 'update_attached_file', $file, $attachment_id );

	$file = _wp_relative_upload_path( $file );
	if ( $file ) {
		return update_post_meta( $attachment_id, '_wp_attached_file', $file );
	} else {
		return delete_post_meta( $attachment_id, '_wp_attached_file' );
	}
}

/**
 * Returns relative path to an uploaded file.
 *
 * The path is relative to the current upload dir.
 *
 * @since 2.9.0
 * @access private
 *
 * @param string $path Full path to the file.
 * @return string Relative path on success, unchanged path on failure.
 */
function _wp_relative_upload_path( $path ) {
	$new_path = $path;

	$uploads = wp_get_upload_dir();
	if ( str_starts_with( $new_path, $uploads['basedir'] ) ) {
			$new_path = str_replace( $uploads['basedir'], '', $new_path );
			$new_path = ltrim( $new_path, '/' );
	}

	/**
	 * Filters the relative path to an uploaded file.
	 *
	 * @since 2.9.0
	 *
	 * @param string $new_path Relative path to the file.
	 * @param string $path     Full path to the file.
	 */
	return apply_filters( '_wp_relative_upload_path', $new_path, $path );
}

/**
 * Retrieves all children of the post parent ID.
 *
 * Normally, without any enhancements, the children would apply to pages. In the
 * context of the inner workings of WordPress, pages, posts, and attachments
 * share the same table, so therefore the functionality could apply to any one
 * of them. It is then noted that while this function does not work on posts, it
 * does not mean that it won't work on posts. It is recommended that you know
 * what context you wish to retrieve the children of.
 *
 * Attachments may also be made the child of a post, so if that is an accurate
 * statement (which needs to be verified), it would then be possible to get
 * all of the attachments for a post. Attachments have since changed since
 * version 2.5, so this is most likely inaccurate, but serves generally as an
 * example of what is possible.
 *
 * The arguments listed as defaults are for this function and also of the
 * get_posts() function. The arguments are combined with the get_children defaults
 * and are then passed to the get_posts() function, which accepts additional arguments.
 * You can replace the defaults in this function, listed below and the additional
 * arguments listed in the get_posts() function.
 *
 * The 'post_parent' is the most important argument and important attention
 * needs to be paid to the $args parameter. If you pass either an object or an
 * integer (number), then just the 'post_parent' is grabbed and everything else
 * is lost. If you don't specify any arguments, then it is assumed that you are
 * in The Loop and the post parent will be grabbed for from the current post.
 *
 * The 'post_parent' argument is the ID to get the children. The 'numberposts'
 * is the amount of posts to retrieve that has a default of '-1', which is
 * used to get all of the posts. Giving a number higher than 0 will only
 * retrieve that amount of posts.
 *
 * The 'post_type' and 'post_status' arguments can be used to choose what
 * criteria of posts to retrieve. The 'post_type' can be anything, but WordPress
 * post types are 'post', 'pages', and 'attachments'. The 'post_status'
 * argument will accept any post status within the write administration panels.
 *
 * @since 2.0.0
 *
 * @see get_posts()
 * @todo Check validity of description.
 *
 * @global WP_Post $post Global post object.
 *
 * @param mixed  $args   Optional. User defined arguments for replacing the defaults. Default empty.
 * @param string $output Optional. The required return type. One of OBJECT, ARRAY_A, or ARRAY_N, which
 *                       correspond to a WP_Post object, an associative array, or a numeric array,
 *                       respectively. Default OBJECT.
 * @return WP_Post[]|array[]|int[] Array of post objects, arrays, or IDs, depending on `$output`.
 */
function get_children( $args = '', $output = OBJECT ) {
	$kids = array();
	if ( empty( $args ) ) {
		if ( isset( $GLOBALS['post'] ) ) {
			$args = array( 'post_parent' => (int) $GLOBALS['post']->post_parent );
		} else {
			return $kids;
		}
	} elseif ( is_object( $args ) ) {
		$args = array( 'post_parent' => (int) $args->post_parent );
	} elseif ( is_numeric( $args ) ) {
		$args = array( 'post_parent' => (int) $args );
	}

	$defaults = array(
		'numberposts' => -1,
		'post_type'   => 'any',
		'post_status' => 'any',
		'post_parent' => 0,
	);

	$parsed_args = wp_parse_args( $args, $defaults );

	$children = get_posts( $parsed_args );

	if ( ! $children ) {
		return $kids;
	}

	if ( ! empty( $parsed_args['fields'] ) ) {
		return $children;
	}

	update_post_cache( $children );

	foreach ( $children as $key => $child ) {
		$kids[ $child->ID ] = $children[ $key ];
	}

	if ( OBJECT === $output ) {
		return $kids;
	} elseif ( ARRAY_A === $output ) {
		$weeuns = array();
		foreach ( (array) $kids as $kid ) {
			$weeuns[ $kid->ID ] = get_object_vars( $kids[ $kid->ID ] );
		}
		return $weeuns;
	} elseif ( ARRAY_N === $output ) {
		$babes = array();
		foreach ( (array) $kids as $kid ) {
			$babes[ $kid->ID ] = array_values( get_object_vars( $kids[ $kid->ID ] ) );
		}
		return $babes;
	} else {
		return $kids;
	}
}

/**
 * Gets extended entry info (<!--more-->).
 *
 * There should not be any space after the second dash and before the word
 * 'more'. There can be text or space(s) after the word 'more', but won't be
 * referenced.
 *
 * The returned array has 'main', 'extended', and 'more_text' keys. Main has the text before
 * the `<!--more-->`. The 'extended' key has the content after the
 * `<!--more-->` comment. The 'more_text' key has the custom "Read More" text.
 *
 * @since 1.0.0
 *
 * @param string $post Post content.
 * @return string[] {
 *     Extended entry info.
 *
 *     @type string $main      Content before the more tag.
 *     @type string $extended  Content after the more tag.
 *     @type string $more_text Custom read more text, or empty string.
 * }
 */
function get_extended( $post ) {
	// Match the new style more links.
	if ( preg_match( '/<!--more(.*?)?-->/', $post, $matches ) ) {
		list($main, $extended) = explode( $matches[0], $post, 2 );
		$more_text             = $matches[1];
	} else {
		$main      = $post;
		$extended  = '';
		$more_text = '';
	}

	// Leading and trailing whitespace.
	$main      = preg_replace( '/^[\s]*(.*)[\s]*$/', '\\1', $main );
	$extended  = preg_replace( '/^[\s]*(.*)[\s]*$/', '\\1', $extended );
	$more_text = preg_replace( '/^[\s]*(.*)[\s]*$/', '\\1', $more_text );

	return array(
		'main'      => $main,
		'extended'  => $extended,
		'more_text' => $more_text,
	);
}

/**
 * Retrieves post data given a post ID or post object.
 *
 * See sanitize_post() for optional $filter values. Also, the parameter
 * `$post`, must be given as a variable, since it is passed by reference.
 *
 * @since 1.5.1
 *
 * @global WP_Post $post Global post object.
 *
 * @param int|object|null  $post   Optional. Post ID or post object. `null`, `false`, `0` and other PHP falsey values
 *                                 return the current global post inside the loop. A numerically valid post ID that
 *                                 points to a non-existent post returns `null`. Defaults to global $post.
 * @param string           $output Optional. The required return type. One of OBJECT, ARRAY_A, or ARRAY_N, which
 *                                 correspond to a WP_Post object, an associative array, or a numeric array,
 *                                 respectively. Default OBJECT.
 * @param string           $filter Optional. Type of filter to apply. Accepts 'raw', 'edit', 'db',
 *                                 or 'display'. Default 'raw'.
 * @return WP_Post|array|null Type corresponding to $output on success or null on failure.
 *                            When $output is OBJECT, a `WP_Post` instance is returned.
 */
function get_post( $post = null, $output = OBJECT, $filter = 'raw' ) {
	if ( empty( $post ) && isset( $GLOBALS['post'] ) ) {
		$post = $GLOBALS['post'];
	}

	if ( $post instanceof WP_Post ) {
		$_post = $post;
	} elseif ( is_object( $post ) ) {
		if ( empty( $post->filter ) ) {
			$_post = sanitize_post( $post, 'raw' );
			$_post = new WP_Post( $_post );
		} elseif ( 'raw' === $post->filter ) {
			$_post = new WP_Post( $post );
		} elseif ( isset( $post->ID ) ) {
			$_post = WP_Post::get_instance( $post->ID );
		} else {
			$_post = null;
		}
	} else {
		$_post = WP_Post::get_instance( $post );
	}

	if ( ! $_post ) {
		return null;
	}

	$_post = $_post->filter( $filter );

	if ( ARRAY_A === $output ) {
		return $_post->to_array();
	} elseif ( ARRAY_N === $output ) {
		return array_values( $_post->to_array() );
	}

	return $_post;
}

/**
 * Retrieves the IDs of the ancestors of a post.
 *
 * @since 2.5.0
 *
 * @param int|WP_Post $post Post ID or post object.
 * @return int[] Array of ancestor IDs or empty array if there are none.
 */
function get_post_ancestors( $post ) {
	$post = get_post( $post );

	if ( ! $post || empty( $post->post_parent ) || $post->post_parent === $post->ID ) {
		return array();
	}

	$ancestors = array();

	$id          = $post->post_parent;
	$ancestors[] = $id;

	while ( $ancestor = get_post( $id ) ) {
		// Loop detection: If the ancestor has been seen before, break.
		if ( empty( $ancestor->post_parent ) || $ancestor->post_parent === $post->ID
			|| in_array( $ancestor->post_parent, $ancestors, true )
		) {
			break;
		}

		$id          = $ancestor->post_parent;
		$ancestors[] = $id;
	}

	return $ancestors;
}

/**
 * Retrieves data from a post field based on Post ID.
 *
 * Examples of the post field will be, 'post_type', 'post_status', 'post_content',
 * etc and based off of the post object property or key names.
 *
 * The context values are based off of the taxonomy filter functions and
 * supported values are found within those functions.
 *
 * @since 2.3.0
 * @since 4.5.0 The `$post` parameter was made optional.
 *
 * @see sanitize_post_field()
 *
 * @param string      $field   Post field name.
 * @param int|WP_Post $post    Optional. Post ID or post object. Defaults to global $post.
 * @param string      $context Optional. How to filter the field. Accepts 'raw', 'edit', 'db',
 *                             or 'display'. Default 'display'.
 * @return int|string|int[] The value of the post field on success, empty string on failure.
 */
function get_post_field( $field, $post = null, $context = 'display' ) {
	$post = get_post( $post );

	if ( ! $post ) {
		return '';
	}

	if ( ! isset( $post->$field ) ) {
		return '';
	}

	return sanitize_post_field( $field, $post->$field, $post->ID, $context );
}

/**
 * Retrieves the mime type of an attachment based on the ID.
 *
 * This function can be used with any post type, but it makes more sense with
 * attachments.
 *
 * @since 2.0.0
 *
 * @param int|WP_Post|null $post Optional. Post ID or post object. Defaults to global $post.
 * @return string|false The mime type on success, false on failure.
 */
function get_post_mime_type( $post = null ) {
	$post = get_post( $post );

	if ( is_object( $post ) ) {
		return $post->post_mime_type;
	}

	return false;
}

/**
 * Retrieves the post status based on the post ID.
 *
 * If the post ID is of an attachment, then the parent post status will be given
 * instead.
 *
 * @since 2.0.0
 *
 * @param int|WP_Post $post Optional. Post ID or post object. Defaults to global $post.
 * @return string|false Post status on success, false on failure.
 */
function get_post_status( $post = null ) {
	// Normalize the post object if necessary, skip normalization if called from get_sample_permalink().
	if ( ! $post instanceof WP_Post || ! isset( $post->filter ) || 'sample' !== $post->filter ) {
		$post = get_post( $post );
	}

	if ( ! is_object( $post ) ) {
		return false;
	}

	$post_status = $post->post_status;

	if (
		'attachment' === $post->post_type &&
		'inherit' === $post_status
	) {
		if (
			0 === $post->post_parent ||
			! get_post( $post->post_parent ) ||
			$post->ID === $post->post_parent
		) {
			// Unattached attachments with inherit status are assumed to be published.
			$post_status = 'publish';
		} elseif ( 'trash' === get_post_status( $post->post_parent ) ) {
			// Get parent status prior to trashing.
			$post_status = get_post_meta( $post->post_parent, '_wp_trash_meta_status', true );

			if ( ! $post_status ) {
				// Assume publish as above.
				$post_status = 'publish';
			}
		} else {
			$post_status = get_post_status( $post->post_parent );
		}
	} elseif (
		'attachment' === $post->post_type &&
		! in_array( $post_status, array( 'private', 'trash', 'auto-draft' ), true )
	) {
		/*
		 * Ensure uninherited attachments have a permitted status either 'private', 'trash', 'auto-draft'.
		 * This is to match the logic in wp_insert_post().
		 *
		 * Note: 'inherit' is excluded from this check as it is resolved to the parent post's
		 * status in the logic block above.
		 */
		$post_status = 'publish';
	}

	/**
	 * Filters the post status.
	 *
	 * @since 4.4.0
	 * @since 5.7.0 The attachment post type is now passed through this filter.
	 *
	 * @param string  $post_status The post status.
	 * @param WP_Post $post        The post object.
	 */
	return apply_filters( 'get_post_status', $post_status, $post );
}

/**
 * Retrieves all of the WordPress supported post statuses.
 *
 * Posts have a limited set of valid status values, this provides the
 * post_status values and descriptions.
 *
 * @since 2.5.0
 *
 * @return string[] Array of post status labels keyed by their status.
 */
function get_post_statuses() {
	$status = array(
		'draft'   => __( 'Draft' ),
		'pending' => __( 'Pending Review' ),
		'private' => __( 'Private' ),
		'publish' => __( 'Published' ),
	);

	return $status;
}

/**
 * Retrieves all of the WordPress support page statuses.
 *
 * Pages have a limited set of valid status values, this provides the
 * post_status values and descriptions.
 *
 * @since 2.5.0
 *
 * @return string[] Array of page status labels keyed by their status.
 */
function get_page_statuses() {
	$status = array(
		'draft'   => __( 'Draft' ),
		'private' => __( 'Private' ),
		'publish' => __( 'Published' ),
	);

	return $status;
}

/**
 * Returns statuses for privacy requests.
 *
 * @since 4.9.6
 * @access private
 *
 * @return string[] Array of privacy request status labels keyed by their status.
 */
function _wp_privacy_statuses() {
	return array(
		'request-pending'   => _x( 'Pending', 'request status' ),      // Pending confirmation from user.
		'request-confirmed' => _x( 'Confirmed', 'request status' ),    // User has confirmed the action.
		'request-failed'    => _x( 'Failed', 'request status' ),       // User failed to confirm the action.
		'request-completed' => _x( 'Completed', 'request status' ),    // Admin has handled the request.
	);
}

/**
 * Registers a post status. Do not use before init.
 *
 * A simple function for creating or modifying a post status based on the
 * parameters given. The function will accept an array (second optional
 * parameter), along with a string for the post status name.
 *
 * Arguments prefixed with an _underscore shouldn't be used by plugins and themes.
 *
 * @since 3.0.0
 *
 * @global stdClass[] $wp_post_statuses Inserts new post status object into the list
 *
 * @param string       $post_status Name of the post status.
 * @param array|string $args {
 *     Optional. Array or string of post status arguments.
 *
 *     @type bool|string $label                     A descriptive name for the post status marked
 *                                                  for translation. Defaults to value of $post_status.
 *     @type array|false $label_count               Nooped plural text from _n_noop() to provide the singular
 *                                                  and plural forms of the label for counts. Default false
 *                                                  which means the `$label` argument will be used for both
 *                                                  the singular and plural forms of this label.
 *     @type bool        $exclude_from_search       Whether to exclude posts with this post status
 *                                                  from search results. Default is value of $internal.
 *     @type bool        $_builtin                  Whether the status is built-in. Core-use only.
 *                                                  Default false.
 *     @type bool        $public                    Whether posts of this status should be shown
 *                                                  in the front end of the site. Default false.
 *     @type bool        $internal                  Whether the status is for internal use only.
 *                                                  Default false.
 *     @type bool        $protected                 Whether posts with this status should be protected.
 *                                                  Default false.
 *     @type bool        $private                   Whether posts with this status should be private.
 *                                                  Default false.
 *     @type bool        $publicly_queryable        Whether posts with this status should be publicly-
 *                                                  queryable. Default is value of $public.
 *     @type bool        $show_in_admin_all_list    Whether to include posts in the edit listing for
 *                                                  their post type. Default is the opposite value
 *                                                  of $internal.
 *     @type bool        $show_in_admin_status_list Show in the list of statuses with post counts at
 *                                                  the top of the edit listings,
 *                                                  e.g. All (12) | Published (9) | My Custom Status (2)
 *                                                  Default is the opposite value of $internal.
 *     @type bool        $date_floating             Whether the post has a floating creation date.
 *                                                  Default to false.
 * }
 * @return object
 */
function register_post_status( $post_status, $args = array() ) {
	global $wp_post_statuses;

	if ( ! is_array( $wp_post_statuses ) ) {
		$wp_post_statuses = array();
	}

	// Args prefixed with an underscore are reserved for internal use.
	$defaults = array(
		'label'                     => false,
		'label_count'               => false,
		'exclude_from_search'       => null,
		'_builtin'                  => false,
		'public'                    => null,
		'internal'                  => null,
		'protected'                 => null,
		'private'                   => null,
		'publicly_queryable'        => null,
		'show_in_admin_status_list' => null,
		'show_in_admin_all_list'    => null,
		'date_floating'             => null,
	);
	$args     = wp_parse_args( $args, $defaults );
	$args     = (object) $args;

	$post_status = sanitize_key( $post_status );
	$args->name  = $post_status;

	// Set various defaults.
	if ( null === $args->public && null === $args->internal && null === $args->protected && null === $args->private ) {
		$args->internal = true;
	}

	if ( null === $args->public ) {
		$args->public = false;
	}

	if ( null === $args->private ) {
		$args->private = false;
	}

	if ( null === $args->protected ) {
		$args->protected = false;
	}

	if ( null === $args->internal ) {
		$args->internal = false;
	}

	if ( null === $args->publicly_queryable ) {
		$args->publicly_queryable = $args->public;
	}

	if ( null === $args->exclude_from_search ) {
		$args->exclude_from_search = $args->internal;
	}

	if ( null === $args->show_in_admin_all_list ) {
		$args->show_in_admin_all_list = ! $args->internal;
	}

	if ( null === $args->show_in_admin_status_list ) {
		$args->show_in_admin_status_list = ! $args->internal;
	}

	if ( null === $args->date_floating ) {
		$args->date_floating = false;
	}

	if ( false === $args->label ) {
		$args->label = $post_status;
	}

	if ( false === $args->label_count ) {
		// phpcs:ignore WordPress.WP.I18n.NonSingularStringLiteralSingular,WordPress.WP.I18n.NonSingularStringLiteralPlural
		$args->label_count = _n_noop( $args->label, $args->label );
	}

	$wp_post_statuses[ $post_status ] = $args;

	return $args;
}

/**
 * Retrieves a post status object by name.
 *
 * @since 3.0.0
 *
 * @see register_post_status()
 *
 * @global stdClass[] $wp_post_statuses List of post statuses.
 *
 * @param string $post_status The name of a registered post status.
 * @return stdClass|null A post status object.
 */
function get_post_status_object( $post_status ) {
	global $wp_post_statuses;

	if ( ! is_string( $post_status ) || empty( $wp_post_statuses[ $post_status ] ) ) {
		return null;
	}

	return $wp_post_statuses[ $post_status ];
}

/**
 * Gets a list of post statuses.
 *
 * @since 3.0.0
 *
 * @see register_post_status()
 *
 * @global stdClass[] $wp_post_statuses List of post statuses.
 *
 * @param array|string $args     Optional. Array or string of post status arguments to compare against
 *                               properties of the global `$wp_post_statuses objects`. Default empty array.
 * @param string       $output   Optional. The type of output to return, either 'names' or 'objects'. Default 'names'.
 * @param string       $operator Optional. The logical operation to perform. 'or' means only one element
 *                               from the array needs to match; 'and' means all elements must match.
 *                               Default 'and'.
 * @return string[]|stdClass[] A list of post status names or objects.
 */
function get_post_stati( $args = array(), $output = 'names', $operator = 'and' ) {
	global $wp_post_statuses;

	$field = ( 'names' === $output ) ? 'name' : false;

	return wp_filter_object_list( $wp_post_statuses, $args, $operator, $field );
}

/**
 * Determines whether the post type is hierarchical.
 *
 * A false return value might also mean that the post type does not exist.
 *
 * @since 3.0.0
 *
 * @see get_post_type_object()
 *
 * @param string $post_type Post type name
 * @return bool Whether post type is hierarchical.
 */
function is_post_type_hierarchical( $post_type ) {
	if ( ! post_type_exists( $post_type ) ) {
		return false;
	}

	$post_type = get_post_type_object( $post_type );
	return $post_type->hierarchical;
}

/**
 * Determines whether a post type is registered.
 *
 * For more information on this and similar theme functions, check out
 * the {@link https://developer.wordpress.org/themes/basics/conditional-tags/
 * Conditional Tags} article in the Theme Developer Handbook.
 *
 * @since 3.0.0
 *
 * @see get_post_type_object()
 *
 * @param string $post_type Post type name.
 * @return bool Whether post type is registered.
 */
function post_type_exists( $post_type ) {
	return (bool) get_post_type_object( $post_type );
}

/**
 * Retrieves the post type of the current post or of a given post.
 *
 * @since 2.1.0
 *
 * @param int|WP_Post|null $post Optional. Post ID or post object. Default is global $post.
 * @return string|false          Post type on success, false on failure.
 */
function get_post_type( $post = null ) {
	$post = get_post( $post );
	if ( $post ) {
		return $post->post_type;
	}

	return false;
}

/**
 * Retrieves a post type object by name.
 *
 * @since 3.0.0
 * @since 4.6.0 Object returned is now an instance of `WP_Post_Type`.
 *
 * @see register_post_type()
 *
 * @global array $wp_post_types List of post types.
 *
 * @param string $post_type The name of a registered post type.
 * @return WP_Post_Type|null WP_Post_Type object if it exists, null otherwise.
 */
function get_post_type_object( $post_type ) {
	global $wp_post_types;

	if ( ! is_scalar( $post_type ) || empty( $wp_post_types[ $post_type ] ) ) {
		return null;
	}

	return $wp_post_types[ $post_type ];
}

/**
 * Gets a list of all registered post type objects.
 *
 * @since 2.9.0
 *
 * @see register_post_type() for accepted arguments.
 *
 * @global array $wp_post_types List of post types.
 *
 * @param array|string $args     Optional. An array of key => value arguments to match against
 *                               the post type objects. Default empty array.
 * @param string       $output   Optional. The type of output to return. Either 'names'
 *                               or 'objects'. Default 'names'.
 * @param string       $operator Optional. The logical operation to perform. 'or' means only one
 *                               element from the array needs to match; 'and' means all elements
 *                               must match; 'not' means no elements may match. Default 'and'.
 * @return string[]|WP_Post_Type[] An array of post type names or objects.
 */
function get_post_types( $args = array(), $output = 'names', $operator = 'and' ) {
	global $wp_post_types;

	$field = ( 'names' === $output ) ? 'name' : false;

	return wp_filter_object_list( $wp_post_types, $args, $operator, $field );
}

/**
 * Registers a post type.
 *
 * Note: Post type registrations should not be hooked before the
 * {@see 'init'} action. Also, any taxonomy connections should be
 * registered via the `$taxonomies` argument to ensure consistency
 * when hooks such as {@see 'parse_query'} or {@see 'pre_get_posts'}
 * are used.
 *
 * Post types can support any number of built-in core features such
 * as meta boxes, custom fields, post thumbnails, post statuses,
 * comments, and more. See the `$supports` argument for a complete
 * list of supported features.
 *
 * @since 2.9.0
 * @since 3.0.0 The `show_ui` argument is now enforced on the new post screen.
 * @since 4.4.0 The `show_ui` argument is now enforced on the post type listing
 *              screen and post editing screen.
 * @since 4.6.0 Post type object returned is now an instance of `WP_Post_Type`.
 * @since 4.7.0 Introduced `show_in_rest`, `rest_base` and `rest_controller_class`
 *              arguments to register the post type in REST API.
 * @since 5.0.0 The `template` and `template_lock` arguments were added.
 * @since 5.3.0 The `supports` argument will now accept an array of arguments for a feature.
 * @since 5.9.0 The `rest_namespace` argument was added.
 *
 * @global array $wp_post_types List of post types.
 *
 * @param string       $post_type Post type key. Must not exceed 20 characters and may only contain
 *                                lowercase alphanumeric characters, dashes, and underscores. See sanitize_key().
 * @param array|string $args {
 *     Array or string of arguments for registering a post type.
 *
 *     @type string       $label                           Name of the post type shown in the menu. Usually plural.
 *                                                         Default is value of $labels['name'].
 *     @type string[]     $labels                          An array of labels for this post type. If not set, post
 *                                                         labels are inherited for non-hierarchical types and page
 *                                                         labels for hierarchical ones. See get_post_type_labels() for a full
 *                                                         list of supported labels.
 *     @type string       $description                     A short descriptive summary of what the post type is.
 *                                                         Default empty.
 *     @type bool         $public                          Whether a post type is intended for use publicly either via
 *                                                         the admin interface or by front-end users. While the default
 *                                                         settings of $exclude_from_search, $publicly_queryable, $show_ui,
 *                                                         and $show_in_nav_menus are inherited from $public, each does not
 *                                                         rely on this relationship and controls a very specific intention.
 *                                                         Default false.
 *     @type bool         $hierarchical                    Whether the post type is hierarchical (e.g. page). Default false.
 *     @type bool         $exclude_from_search             Whether to exclude posts with this post type from front end search
 *                                                         results. Default is the opposite value of $public.
 *     @type bool         $publicly_queryable              Whether queries can be performed on the front end for the post type
 *                                                         as part of parse_request(). Endpoints would include:
 *                                                          * ?post_type={post_type_key}
 *                                                          * ?{post_type_key}={single_post_slug}
 *                                                          * ?{post_type_query_var}={single_post_slug}
 *                                                         If not set, the default is inherited from $public.
 *     @type bool         $show_ui                         Whether to generate and allow a UI for managing this post type in the
 *                                                         admin. Default is value of $public.
 *     @type bool|string  $show_in_menu                    Where to show the post type in the admin menu. To work, $show_ui
 *                                                         must be true. If true, the post type is shown in its own top level
 *                                                         menu. If false, no menu is shown. If a string of an existing top
 *                                                         level menu ('tools.php' or 'edit.php?post_type=page', for example), the
 *                                                         post type will be placed as a sub-menu of that.
 *                                                         Default is value of $show_ui.
 *     @type bool         $show_in_nav_menus               Makes this post type available for selection in navigation menus.
 *                                                         Default is value of $public.
 *     @type bool         $show_in_admin_bar               Makes this post type available via the admin bar. Default is value
 *                                                         of $show_in_menu.
 *     @type bool         $show_in_rest                    Whether to include the post type in the REST API. Set this to true
 *                                                         for the post type to be available in the block editor.
 *     @type string       $rest_base                       To change the base URL of REST API route. Default is $post_type.
 *     @type string       $rest_namespace                  To change the namespace URL of REST API route. Default is wp/v2.
 *     @type string       $rest_controller_class           REST API controller class name. Default is 'WP_REST_Posts_Controller'.
 *     @type string|bool  $autosave_rest_controller_class  REST API controller class name. Default is 'WP_REST_Autosaves_Controller'.
 *     @type string|bool  $revisions_rest_controller_class REST API controller class name. Default is 'WP_REST_Revisions_Controller'.
 *     @type bool         $late_route_registration         A flag to direct the REST API controllers for autosave / revisions
 *                                                         should be registered before/after the post type controller.
 *     @type int          $menu_position                   The position in the menu order the post type should appear. To work,
 *                                                         $show_in_menu must be true. Default null (at the bottom).
 *     @type string       $menu_icon                       The URL to the icon to be used for this menu. Pass a base64-encoded
 *                                                         SVG using a data URI, which will be colored to match the color scheme
 *                                                         -- this should begin with 'data:image/svg+xml;base64,'. Pass the name
 *                                                         of a Dashicons helper class to use a font icon, e.g.
 *                                                        'dashicons-chart-pie'. Pass 'none' to leave div.wp-menu-image empty
 *                                                         so an icon can be added via CSS. Defaults to use the posts icon.
 *     @type string|array $capability_type                 The string to use to build the read, edit, and delete capabilities.
 *                                                         May be passed as an array to allow for alternative plurals when using
 *                                                         this argument as a base to construct the capabilities, e.g.
 *                                                         array('story', 'stories'). Default 'post'.
 *     @type string[]     $capabilities                    Array of capabilities for this post type. $capability_type is used
 *                                                         as a base to construct capabilities by default.
 *                                                         See get_post_type_capabilities().
 *     @type bool         $map_meta_cap                    Whether to use the internal default meta capability handling.
 *                                                         Default false.
 *     @type array|false  $supports                        Core feature(s) the post type supports. Serves as an alias for calling
 *                                                         add_post_type_support() directly. Core features include 'title',
 *                                                         'editor', 'comments', 'revisions', 'trackbacks', 'author', 'excerpt',
 *                                                         'page-attributes', 'thumbnail', 'custom-fields', and 'post-formats'.
 *                                                         Additionally, the 'revisions' feature dictates whether the post type
 *                                                         will store revisions, the 'autosave' feature dictates whether the post type
 *                                                         will be autosaved, and the 'comments' feature dictates whether the
 *                                                         comments count will show on the edit screen. For backward compatibility reasons,
 *                                                         adding 'editor' support implies 'autosave' support too. A feature can also be
 *                                                         specified as an array of arguments to provide additional information
 *                                                         about supporting that feature.
 *                                                         Example: `array( 'my_feature', array( 'field' => 'value' ) )`.
 *                                                         If false, no features will be added.
 *                                                         Default is an array containing 'title' and 'editor'.
 *     @type callable     $register_meta_box_cb            Provide a callback function that sets up the meta boxes for the
 *                                                         edit form. Do remove_meta_box() and add_meta_box() calls in the
 *                                                         callback. Default null.
 *     @type string[]     $taxonomies                      An array of taxonomy identifiers that will be registered for the
 *                                                         post type. Taxonomies can be registered later with register_taxonomy()
 *                                                         or register_taxonomy_for_object_type().
 *                                                         Default empty array.
 *     @type bool|string  $has_archive                     Whether there should be post type archives, or if a string, the
 *                                                         archive slug to use. Will generate the proper rewrite rules if
 *                                                         $rewrite is enabled. Default false.
 *     @type bool|array   $rewrite                         {
 *         Triggers the handling of rewrites for this post type. To prevent rewrite, set to false.
 *         Defaults to true, using $post_type as slug. To specify rewrite rules, an array can be
 *         passed with any of these keys:
 *
 *         @type string $slug       Customize the permastruct slug. Defaults to $post_type key.
 *         @type bool   $with_front Whether the permastruct should be prepended with WP_Rewrite::$front.
 *                                  Default true.
 *         @type bool   $feeds      Whether the feed permastruct should be built for this post type.
 *                                  Default is value of $has_archive.
 *         @type bool   $pages      Whether the permastruct should provide for pagination. Default true.
 *         @type int    $ep_mask    Endpoint mask to assign. If not specified and permalink_epmask is set,
 *                                  inherits from $permalink_epmask. If not specified and permalink_epmask
 *                                  is not set, defaults to EP_PERMALINK.
 *     }
 *     @type string|bool  $query_var                      Sets the query_var key for this post type. Defaults to $post_type
 *                                                        key. If false, a post type cannot be loaded at
 *                                                        ?{query_var}={post_slug}. If specified as a string, the query
 *                                                        ?{query_var_string}={post_slug} will be valid.
 *     @type bool         $can_export                     Whether to allow this post type to be exported. Default true.
 *     @type bool         $delete_with_user               Whether to delete posts of this type when deleting a user.
 *                                                          * If true, posts of this type belonging to the user will be moved
 *                                                            to Trash when the user is deleted.
 *                                                          * If false, posts of this type belonging to the user will *not*
 *                                                            be trashed or deleted.
 *                                                          * If not set (the default), posts are trashed if post type supports
 *                                                            the 'author' feature. Otherwise posts are not trashed or deleted.
 *                                                        Default null.
 *     @type array        $template                       Array of blocks to use as the default initial state for an editor
 *                                                        session. Each item should be an array containing block name and
 *                                                        optional attributes. Default empty array.
 *     @type string|false $template_lock                  Whether the block template should be locked if $template is set.
 *                                                          * If set to 'all', the user is unable to insert new blocks,
 *                                                            move existing blocks and delete blocks.
 *                                                          * If set to 'insert', the user is able to move existing blocks
 *                                                            but is unable to insert new blocks and delete blocks.
 *                                                          * If set to 'contentOnly', the user is only able to edit the content
 *                                                            of existing blocks.
 *                                                        Default false.
 *     @type bool         $_builtin                       FOR INTERNAL USE ONLY! True if this post type is a native or
 *                                                        "built-in" post_type. Default false.
 *     @type string       $_edit_link                     FOR INTERNAL USE ONLY! URL segment to use for edit link of
 *                                                        this post type. Default 'post.php?post=%d'.
 * }
 * @return WP_Post_Type|WP_Error The registered post type object on success,
 *                               WP_Error object on failure.
 */
function register_post_type( $post_type, $args = array() ) {
	global $wp_post_types;

	if ( ! is_array( $wp_post_types ) ) {
		$wp_post_types = array();
	}

	// Sanitize post type name.
	$post_type = sanitize_key( $post_type );

	if ( empty( $post_type ) || strlen( $post_type ) > 20 ) {
		_doing_it_wrong( __FUNCTION__, __( 'Post type names must be between 1 and 20 characters in length.' ), '4.2.0' );
		return new WP_Error( 'post_type_length_invalid', __( 'Post type names must be between 1 and 20 characters in length.' ) );
	}

	$post_type_object = new WP_Post_Type( $post_type, $args );
	$post_type_object->add_supports();
	$post_type_object->add_rewrite_rules();
	$post_type_object->register_meta_boxes();

	$wp_post_types[ $post_type ] = $post_type_object;

	$post_type_object->add_hooks();
	$post_type_object->register_taxonomies();

	/**
	 * Fires after a post type is registered.
	 *
	 * @since 3.3.0
	 * @since 4.6.0 Converted the `$post_type` parameter to accept a WP_Post_Type object.
	 *
	 * @param string       $post_type        Post type.
	 * @param WP_Post_Type $post_type_object Arguments used to register the post type.
	 */
	do_action( 'registered_post_type', $post_type, $post_type_object );

	/**
	 * Fires after a specific post type is registered.
	 *
	 * The dynamic portion of the filter name, `$post_type`, refers to the post type key.
	 *
	 * Possible hook names include:
	 *
	 *  - `registered_post_type_post`
	 *  - `registered_post_type_page`
	 *
	 * @since 6.0.0
	 *
	 * @param string       $post_type        Post type.
	 * @param WP_Post_Type $post_type_object Arguments used to register the post type.
	 */
	do_action( "registered_post_type_{$post_type}", $post_type, $post_type_object );

	return $post_type_object;
}

/**
 * Unregisters a post type.
 *
 * Cannot be used to unregister built-in post types.
 *
 * @since 4.5.0
 *
 * @global array $wp_post_types List of post types.
 *
 * @param string $post_type Post type to unregister.
 * @return true|WP_Error True on success, WP_Error on failure or if the post type doesn't exist.
 */
function unregister_post_type( $post_type ) {
	global $wp_post_types;

	if ( ! post_type_exists( $post_type ) ) {
		return new WP_Error( 'invalid_post_type', __( 'Invalid post type.' ) );
	}

	$post_type_object = get_post_type_object( $post_type );

	// Do not allow unregistering internal post types.
	if ( $post_type_object->_builtin ) {
		return new WP_Error( 'invalid_post_type', __( 'Unregistering a built-in post type is not allowed' ) );
	}

	$post_type_object->remove_supports();
	$post_type_object->remove_rewrite_rules();
	$post_type_object->unregister_meta_boxes();
	$post_type_object->remove_hooks();
	$post_type_object->unregister_taxonomies();

	unset( $wp_post_types[ $post_type ] );

	/**
	 * Fires after a post type was unregistered.
	 *
	 * @since 4.5.0
	 *
	 * @param string $post_type Post type key.
	 */
	do_action( 'unregistered_post_type', $post_type );

	return true;
}

/**
 * Builds an object with all post type capabilities out of a post type object
 *
 * Post type capabilities use the 'capability_type' argument as a base, if the
 * capability is not set in the 'capabilities' argument array or if the
 * 'capabilities' argument is not supplied.
 *
 * The capability_type argument can optionally be registered as an array, with
 * the first value being singular and the second plural, e.g. array('story, 'stories')
 * Otherwise, an 's' will be added to the value for the plural form. After
 * registration, capability_type will always be a string of the singular value.
 *
 * By default, the following keys are accepted as part of the capabilities array:
 *
 * - edit_post, read_post, and delete_post are meta capabilities, which are then
 *   generally mapped to corresponding primitive capabilities depending on the
 *   context, which would be the post being edited/read/deleted and the user or
 *   role being checked. Thus these capabilities would generally not be granted
 *   directly to users or roles.
 *
 * - edit_posts - Controls whether objects of this post type can be edited.
 * - edit_others_posts - Controls whether objects of this type owned by other users
 *   can be edited. If the post type does not support an author, then this will
 *   behave like edit_posts.
 * - delete_posts - Controls whether objects of this post type can be deleted.
 * - publish_posts - Controls publishing objects of this post type.
 * - read_private_posts - Controls whether private objects can be read.
 * - create_posts - Controls whether objects of this post type can be created.
 *
 * These primitive capabilities are checked in core in various locations.
 * There are also six other primitive capabilities which are not referenced
 * directly in core, except in map_meta_cap(), which takes the three aforementioned
 * meta capabilities and translates them into one or more primitive capabilities
 * that must then be checked against the user or role, depending on the context.
 *
 * - read - Controls whether objects of this post type can be read.
 * - delete_private_posts - Controls whether private objects can be deleted.
 * - delete_published_posts - Controls whether published objects can be deleted.
 * - delete_others_posts - Controls whether objects owned by other users can be
 *   can be deleted. If the post type does not support an author, then this will
 *   behave like delete_posts.
 * - edit_private_posts - Controls whether private objects can be edited.
 * - edit_published_posts - Controls whether published objects can be edited.
 *
 * These additional capabilities are only used in map_meta_cap(). Thus, they are
 * only assigned by default if the post type is registered with the 'map_meta_cap'
 * argument set to true (default is false).
 *
 * @since 3.0.0
 * @since 5.4.0 'delete_posts' is included in default capabilities.
 *
 * @see register_post_type()
 * @see map_meta_cap()
 *
 * @param object $args Post type registration arguments.
 * @return object {
 *     Object with all the capabilities as member variables.
 *
 *     @type string $edit_post              Capability to edit a post.
 *     @type string $read_post              Capability to read a post.
 *     @type string $delete_post            Capability to delete a post.
 *     @type string $edit_posts             Capability to edit posts.
 *     @type string $edit_others_posts      Capability to edit others' posts.
 *     @type string $delete_posts           Capability to delete posts.
 *     @type string $publish_posts          Capability to publish posts.
 *     @type string $read_private_posts     Capability to read private posts.
 *     @type string $create_posts           Capability to create posts.
 *     @type string $read                   Optional. Capability to read a post.
 *     @type string $delete_private_posts   Optional. Capability to delete private posts.
 *     @type string $delete_published_posts Optional. Capability to delete published posts.
 *     @type string $delete_others_posts    Optional. Capability to delete others' posts.
 *     @type string $edit_private_posts     Optional. Capability to edit private posts.
 *     @type string $edit_published_posts   Optional. Capability to edit published posts.
 * }
 */
function get_post_type_capabilities( $args ) {
	if ( ! is_array( $args->capability_type ) ) {
		$args->capability_type = array( $args->capability_type, $args->capability_type . 's' );
	}

	// Singular base for meta capabilities, plural base for primitive capabilities.
	list( $singular_base, $plural_base ) = $args->capability_type;

	$default_capabilities = array(
		// Meta capabilities.
		'edit_post'          => 'edit_' . $singular_base,
		'read_post'          => 'read_' . $singular_base,
		'delete_post'        => 'delete_' . $singular_base,
		// Primitive capabilities used outside of map_meta_cap():
		'edit_posts'         => 'edit_' . $plural_base,
		'edit_others_posts'  => 'edit_others_' . $plural_base,
		'delete_posts'       => 'delete_' . $plural_base,
		'publish_posts'      => 'publish_' . $plural_base,
		'read_private_posts' => 'read_private_' . $plural_base,
	);

	// Primitive capabilities used within map_meta_cap():
	if ( $args->map_meta_cap ) {
		$default_capabilities_for_mapping = array(
			'read'                   => 'read',
			'delete_private_posts'   => 'delete_private_' . $plural_base,
			'delete_published_posts' => 'delete_published_' . $plural_base,
			'delete_others_posts'    => 'delete_others_' . $plural_base,
			'edit_private_posts'     => 'edit_private_' . $plural_base,
			'edit_published_posts'   => 'edit_published_' . $plural_base,
		);
		$default_capabilities             = array_merge( $default_capabilities, $default_capabilities_for_mapping );
	}

	$capabilities = array_merge( $default_capabilities, $args->capabilities );

	// Post creation capability simply maps to edit_posts by default:
	if ( ! isset( $capabilities['create_posts'] ) ) {
		$capabilities['create_posts'] = $capabilities['edit_posts'];
	}

	// Remember meta capabilities for future reference.
	if ( $args->map_meta_cap ) {
		_post_type_meta_capabilities( $capabilities );
	}

	return (object) $capabilities;
}

/**
 * Stores or returns a list of post type meta caps for map_meta_cap().
 *
 * @since 3.1.0
 * @access private
 *
 * @global array $post_type_meta_caps Used to store meta capabilities.
 *
 * @param string[] $capabilities Post type meta capabilities.
 */
function _post_type_meta_capabilities( $capabilities = null ) {
	global $post_type_meta_caps;

	foreach ( $capabilities as $core => $custom ) {
		if ( in_array( $core, array( 'read_post', 'delete_post', 'edit_post' ), true ) ) {
			$post_type_meta_caps[ $custom ] = $core;
		}
	}
}

/**
 * Builds an object with all post type labels out of a post type object.
 *
 * Accepted keys of the label array in the post type object:
 *
 * - `name` - General name for the post type, usually plural. The same and overridden
 *          by `$post_type_object->label`. Default is 'Posts' / 'Pages'.
 * - `singular_name` - Name for one object of this post type. Default is 'Post' / 'Page'.
 * - `add_new` - Label for adding a new item. Default is 'Add Post' / 'Add Page'.
 * - `add_new_item` - Label for adding a new singular item. Default is 'Add Post' / 'Add Page'.
 * - `edit_item` - Label for editing a singular item. Default is 'Edit Post' / 'Edit Page'.
 * - `new_item` - Label for the new item page title. Default is 'New Post' / 'New Page'.
 * - `view_item` - Label for viewing a singular item. Default is 'View Post' / 'View Page'.
 * - `view_items` - Label for viewing post type archives. Default is 'View Posts' / 'View Pages'.
 * - `search_items` - Label for searching plural items. Default is 'Search Posts' / 'Search Pages'.
 * - `not_found` - Label used when no items are found. Default is 'No posts found' / 'No pages found'.
 * - `not_found_in_trash` - Label used when no items are in the Trash. Default is 'No posts found in Trash' /
 *                        'No pages found in Trash'.
 * - `parent_item_colon` - Label used to prefix parents of hierarchical items. Not used on non-hierarchical
 *                       post types. Default is 'Parent Page:'.
 * - `all_items` - Label to signify all items in a submenu link. Default is 'All Posts' / 'All Pages'.
 * - `archives` - Label for archives in nav menus. Default is 'Post Archives' / 'Page Archives'.
 * - `attributes` - Label for the attributes meta box. Default is 'Post Attributes' / 'Page Attributes'.
 * - `insert_into_item` - Label for the media frame button. Default is 'Insert into post' / 'Insert into page'.
 * - `uploaded_to_this_item` - Label for the media frame filter. Default is 'Uploaded to this post' /
 *                           'Uploaded to this page'.
 * - `featured_image` - Label for the featured image meta box title. Default is 'Featured image'.
 * - `set_featured_image` - Label for setting the featured image. Default is 'Set featured image'.
 * - `remove_featured_image` - Label for removing the featured image. Default is 'Remove featured image'.
 * - `use_featured_image` - Label in the media frame for using a featured image. Default is 'Use as featured image'.
 * - `menu_name` - Label for the menu name. Default is the same as `name`.
 * - `filter_items_list` - Label for the table views hidden heading. Default is 'Filter posts list' /
 *                       'Filter pages list'.
 * - `filter_by_date` - Label for the date filter in list tables. Default is 'Filter by date'.
 * - `items_list_navigation` - Label for the table pagination hidden heading. Default is 'Posts list navigation' /
 *                           'Pages list navigation'.
 * - `items_list` - Label for the table hidden heading. Default is 'Posts list' / 'Pages list'.
 * - `item_published` - Label used when an item is published. Default is 'Post published.' / 'Page published.'
 * - `item_published_privately` - Label used when an item is published with private visibility.
 *                              Default is 'Post published privately.' / 'Page published privately.'
 * - `item_reverted_to_draft` - Label used when an item is switched to a draft.
 *                            Default is 'Post reverted to draft.' / 'Page reverted to draft.'
 * - `item_trashed` - Label used when an item is moved to Trash. Default is 'Post trashed.' / 'Page trashed.'
 * - `item_scheduled` - Label used when an item is scheduled for publishing. Default is 'Post scheduled.' /
 *                    'Page scheduled.'
 * - `item_updated` - Label used when an item is updated. Default is 'Post updated.' / 'Page updated.'
 * - `item_link` - Title for a navigation link block variation. Default is 'Post Link' / 'Page Link'.
 * - `item_link_description` - Description for a navigation link block variation. Default is 'A link to a post.' /
 *                             'A link to a page.'
 *
 * Above, the first default value is for non-hierarchical post types (like posts)
 * and the second one is for hierarchical post types (like pages).
 *
 * Note: To set labels used in post type admin notices, see the {@see 'post_updated_messages'} filter.
 *
 * @since 3.0.0
 * @since 4.3.0 Added the `featured_image`, `set_featured_image`, `remove_featured_image`,
 *              and `use_featured_image` labels.
 * @since 4.4.0 Added the `archives`, `insert_into_item`, `uploaded_to_this_item`, `filter_items_list`,
 *              `items_list_navigation`, and `items_list` labels.
 * @since 4.6.0 Converted the `$post_type` parameter to accept a `WP_Post_Type` object.
 * @since 4.7.0 Added the `view_items` and `attributes` labels.
 * @since 5.0.0 Added the `item_published`, `item_published_privately`, `item_reverted_to_draft`,
 *              `item_scheduled`, and `item_updated` labels.
 * @since 5.7.0 Added the `filter_by_date` label.
 * @since 5.8.0 Added the `item_link` and `item_link_description` labels.
 * @since 6.3.0 Added the `item_trashed` label.
 * @since 6.4.0 Changed default values for the `add_new` label to include the type of content.
 *              This matches `add_new_item` and provides more context for better accessibility.
 * @since 6.6.0 Added the `template_name` label.
 * @since 6.7.0 Restored pre-6.4.0 defaults for the `add_new` label and updated documentation.
 *              Updated core usage to reference `add_new_item`.
 *
 * @access private
 *
 * @param object|WP_Post_Type $post_type_object Post type object.
 * @return object Object with all the labels as member variables.
 */
function get_post_type_labels( $post_type_object ) {
	$nohier_vs_hier_defaults = WP_Post_Type::get_default_labels();

	$nohier_vs_hier_defaults['menu_name'] = $nohier_vs_hier_defaults['name'];

	$labels = _get_custom_object_labels( $post_type_object, $nohier_vs_hier_defaults );

	if ( ! isset( $post_type_object->labels->template_name ) && isset( $post_type_object->labels->singular_name ) ) {
			/* translators: %s: Post type name. */
			$labels->template_name = sprintf( __( 'Single item: %s' ), $post_type_object->labels->singular_name );
	}

	$post_type = $post_type_object->name;

	$default_labels = clone $labels;

	/**
	 * Filters the labels of a specific post type.
	 *
	 * The dynamic portion of the hook name, `$post_type`, refers to
	 * the post type slug.
	 *
	 * Possible hook names include:
	 *
	 *  - `post_type_labels_post`
	 *  - `post_type_labels_page`
	 *  - `post_type_labels_attachment`
	 *
	 * @since 3.5.0
	 *
	 * @see get_post_type_labels() for the full list of labels.
	 *
	 * @param object $labels Object with labels for the post type as member variables.
	 */
	$labels = apply_filters( "post_type_labels_{$post_type}", $labels );

	// Ensure that the filtered labels contain all required default values.
	$labels = (object) array_merge( (array) $default_labels, (array) $labels );

	return $labels;
}

/**
 * Builds an object with custom-something object (post type, taxonomy) labels
 * out of a custom-something object
 *
 * @since 3.0.0
 * @access private
 *
 * @param object $data_object             A custom-something object.
 * @param array  $nohier_vs_hier_defaults Hierarchical vs non-hierarchical default labels.
 * @return object Object containing labels for the given custom-something object.
 */
function _get_custom_object_labels( $data_object, $nohier_vs_hier_defaults ) {
	$data_object->labels = (array) $data_object->labels;

	if ( isset( $data_object->label ) && empty( $data_object->labels['name'] ) ) {
		$data_object->labels['name'] = $data_object->label;
	}

	if ( ! isset( $data_object->labels['singular_name'] ) && isset( $data_object->labels['name'] ) ) {
		$data_object->labels['singular_name'] = $data_object->labels['name'];
	}

	if ( ! isset( $data_object->labels['name_admin_bar'] ) ) {
		$data_object->labels['name_admin_bar'] = $data_object->labels['singular_name'] ?? $data_object->name;
	}

	if ( ! isset( $data_object->labels['menu_name'] ) && isset( $data_object->labels['name'] ) ) {
		$data_object->labels['menu_name'] = $data_object->labels['name'];
	}

	if ( ! isset( $data_object->labels['all_items'] ) && isset( $data_object->labels['menu_name'] ) ) {
		$data_object->labels['all_items'] = $data_object->labels['menu_name'];
	}

	if ( ! isset( $data_object->labels['archives'] ) && isset( $data_object->labels['all_items'] ) ) {
		$data_object->labels['archives'] = $data_object->labels['all_items'];
	}

	$defaults = array();
	foreach ( $nohier_vs_hier_defaults as $key => $value ) {
		$defaults[ $key ] = $data_object->hierarchical ? $value[1] : $value[0];
	}

	$labels              = array_merge( $defaults, $data_object->labels );
	$data_object->labels = (object) $data_object->labels;

	return (object) $labels;
}

/**
 * Adds submenus for post types.
 *
 * @access private
 * @since 3.1.0
 */
function _add_post_type_submenus() {
	foreach ( get_post_types( array( 'show_ui' => true ) ) as $ptype ) {
		$ptype_obj = get_post_type_object( $ptype );
		// Sub-menus only.
		if ( ! $ptype_obj->show_in_menu || true === $ptype_obj->show_in_menu ) {
			continue;
		}
		add_submenu_page( $ptype_obj->show_in_menu, $ptype_obj->labels->name, $ptype_obj->labels->all_items, $ptype_obj->cap->edit_posts, "edit.php?post_type=$ptype" );
	}
}

/**
 * Registers support of certain features for a post type.
 *
 * All core features are directly associated with a functional area of the edit
 * screen, such as the editor or a meta box. Features include: 'title', 'editor',
 * 'comments', 'revisions', 'trackbacks', 'author', 'excerpt', 'page-attributes',
 * 'thumbnail', 'custom-fields', and 'post-formats'.
 *
 * Additionally, the 'revisions' feature dictates whether the post type will
 * store revisions, the 'autosave' feature dictates whether the post type
 * will be autosaved, and the 'comments' feature dictates whether the comments
 * count will show on the edit screen.
 *
 * A third, optional parameter can also be passed along with a feature to provide
 * additional information about supporting that feature.
 *
 * Example usage:
 *
 *     add_post_type_support( 'my_post_type', 'comments' );
 *     add_post_type_support( 'my_post_type', array(
 *         'author', 'excerpt',
 *     ) );
 *     add_post_type_support( 'my_post_type', 'my_feature', array(
 *         'field' => 'value',
 *     ) );
 *
 * @since 3.0.0
 * @since 5.3.0 Formalized the existing and already documented `...$args` parameter
 *              by adding it to the function signature.
 *
 * @global array $_wp_post_type_features
 *
 * @param string       $post_type The post type for which to add the feature.
 * @param string|array $feature   The feature being added, accepts an array of
 *                                feature strings or a single string.
 * @param mixed        ...$args   Optional extra arguments to pass along with certain features.
 */
function add_post_type_support( $post_type, $feature, ...$args ) {
	global $_wp_post_type_features;

	$features = (array) $feature;
	foreach ( $features as $feature ) {
		if ( $args ) {
			$_wp_post_type_features[ $post_type ][ $feature ] = $args;
		} else {
			$_wp_post_type_features[ $post_type ][ $feature ] = true;
		}
	}
}

/**
 * Removes support for a feature from a post type.
 *
 * @since 3.0.0
 *
 * @global array $_wp_post_type_features
 *
 * @param string $post_type The post type for which to remove the feature.
 * @param string $feature   The feature being removed.
 */
function remove_post_type_support( $post_type, $feature ) {
	global $_wp_post_type_features;

	unset( $_wp_post_type_features[ $post_type ][ $feature ] );
}

/**
 * Gets all the post type features
 *
 * @since 3.4.0
 *
 * @global array $_wp_post_type_features
 *
 * @param string $post_type The post type.
 * @return array Post type supports list.
 */
function get_all_post_type_supports( $post_type ) {
	global $_wp_post_type_features;
	return $_wp_post_type_features[ $post_type ] ?? array();
}

/**
 * Checks a post type's support for a given feature.
 *
 * @since 3.0.0
 *
 * @global array $_wp_post_type_features
 *
 * @param string $post_type The post type being checked.
 * @param string $feature   The feature being checked.
 * @return bool Whether the post type supports the given feature.
 */
function post_type_supports( $post_type, $feature ) {
	global $_wp_post_type_features;

	return ( isset( $_wp_post_type_features[ $post_type ][ $feature ] ) );
}
/**
 * Retrieves a list of post type names that support a specific feature.
 *
 * @since 4.5.0
 *
 * @global array $_wp_post_type_features Post type features
 *
 * @param array|string $feature  Single feature or an array of features the post types should support.
 * @param string       $operator Optional. The logical operation to perform. 'or' means
 *                               only one element from the array needs to match; 'and'
 *                               means all elements must match; 'not' means no elements may
 *                               match. Default 'and'.
 * @return string[] A list of post type names.
 */
function get_post_types_by_support( $feature, $operator = 'and' ) {
	global $_wp_post_type_features;

	$features = array_fill_keys( (array) $feature, true );

	return array_keys( wp_filter_object_list( $_wp_post_type_features, $features, $operator ) );
}

/**
 * Updates the post type for the post ID.
 *
 * The page or post cache will be cleaned for the post ID.
 *
 * @since 2.5.0
 *
 * @global wpdb $wpdb WordPress database abstraction object.
 *
 * @param int    $post_id   Optional. Post ID to change post type. Default 0.
 * @param string $post_type Optional. Post type. Accepts 'post' or 'page' to
 *                          name a few. Default 'post'.
 * @return int|false Amount of rows changed. Should be 1 for success and 0 for failure.
 */
function set_post_type( $post_id = 0, $post_type = 'post' ) {
	global $wpdb;

	$post_type = sanitize_post_field( 'post_type', $post_type, $post_id, 'db' );
	$return    = $wpdb->update( $wpdb->posts, array( 'post_type' => $post_type ), array( 'ID' => $post_id ) );

	clean_post_cache( $post_id );

	return $return;
}

/**
 * Determines whether a post t
