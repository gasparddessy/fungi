<?php
/**
 * Refungi child theme.
 *
 * Enqueues the parent stylesheet, this theme's style.css, and the override
 * file in assets/css/custom.css. Template overrides, when needed, are copies
 * of parent templates placed in this directory — the parent theme stays on
 * the server and out of Git.
 *
 * @package Refungi_Child
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Load parent and child styles the standard WordPress way.
 *
 * Some commercial parents also print a generated stylesheet. Rules that must
 * win live in assets/css/custom.css. This callback runs at priority 20 so it
 * is registered after the default wp_enqueue_scripts priority of 10.
 */
function refungi_child_enqueue_styles() {
	$parent         = wp_get_theme( get_template() );
	$parent_version = $parent->exists() ? $parent->get( 'Version' ) : null;

	wp_enqueue_style(
		'refungi-parent-style',
		get_template_directory_uri() . '/style.css',
		array(),
		$parent_version
	);

	wp_enqueue_style(
		'refungi-child-style',
		get_stylesheet_uri(),
		array( 'refungi-parent-style' ),
		wp_get_theme()->get( 'Version' )
	);

	$overrides_path = get_stylesheet_directory() . '/assets/css/custom.css';

	wp_enqueue_style(
		'refungi-child-overrides',
		get_stylesheet_directory_uri() . '/assets/css/custom.css',
		array( 'refungi-child-style' ),
		file_exists( $overrides_path ) ? (string) filemtime( $overrides_path ) : wp_get_theme()->get( 'Version' )
	);
}
add_action( 'wp_enqueue_scripts', 'refungi_child_enqueue_styles', 20 );
