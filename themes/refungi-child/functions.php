<?php
/**
 * Refungi child theme.
 *
 * @package Refungi_Child
 */

if ( ! defined( 'ABSPATH' ) ) {
	exit;
}

/**
 * Enqueue the parent stylesheet, this theme's stylesheet, then local overrides.
 *
 * This is the standard WordPress child-theme load order. The parent theme may
 * enqueue additional styles of its own; those keep their own handles.
 */
function refungi_child_enqueue_styles() {
	$theme  = wp_get_theme();
	$parent = $theme->parent();
	$deps   = array();

	if ( $parent instanceof WP_Theme ) {
		wp_enqueue_style(
			'refungi-parent-style',
			get_template_directory_uri() . '/style.css',
			array(),
			$parent->get( 'Version' )
		);
		$deps[] = 'refungi-parent-style';
	}

	wp_enqueue_style(
		'refungi-child-style',
		get_stylesheet_uri(),
		$deps,
		$theme->get( 'Version' )
	);

	$overrides_path = get_stylesheet_directory() . '/assets/css/overrides.css';
	$overrides_ver  = file_exists( $overrides_path ) ? (string) filemtime( $overrides_path ) : $theme->get( 'Version' );

	wp_enqueue_style(
		'refungi-child-overrides',
		get_stylesheet_directory_uri() . '/assets/css/overrides.css',
		array( 'refungi-child-style' ),
		$overrides_ver
	);
}
add_action( 'wp_enqueue_scripts', 'refungi_child_enqueue_styles' );
