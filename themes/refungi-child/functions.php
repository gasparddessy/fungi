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
 * Enqueue Bridge's styles, then this theme's stylesheet and overrides.
 *
 * Bridge's style.css is only the WordPress theme header. The CSS that actually
 * styles the site is css/stylesheet.min.css. Bridge registers that file during
 * wp_enqueue_scripts at the default priority, so this runs later and prints
 * after it. The child theme directory stays refungi-child.
 */
function refungi_child_enqueue_styles() {
	$theme          = wp_get_theme();
	$parent         = $theme->parent();
	$parent_version = ( $parent instanceof WP_Theme ) ? $parent->get( 'Version' ) : null;
	$deps           = array();

	wp_enqueue_style(
		'refungi-parent-style',
		get_template_directory_uri() . '/style.css',
		array(),
		$parent_version
	);
	$deps[] = 'refungi-parent-style';

	$bridge_main = refungi_child_enqueue_bridge_stylesheet( $parent_version );
	if ( $bridge_main !== '' ) {
		$deps[] = $bridge_main;
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
add_action( 'wp_enqueue_scripts', 'refungi_child_enqueue_styles', 20 );

/**
 * Enqueue Bridge's compiled stylesheet once.
 *
 * Reuses the handle Bridge already registered when its src is
 * css/stylesheet.min.css. Otherwise loads that file directly if it exists.
 *
 * @param string|null $version Parent theme version.
 * @return string Handle to depend on, or an empty string when the file is absent.
 */
function refungi_child_enqueue_bridge_stylesheet( $version ) {
	$relative = '/css/stylesheet.min.css';
	$handle   = refungi_child_find_style_handle( $relative );

	if ( $handle !== '' ) {
		wp_enqueue_style( $handle );
		return $handle;
	}

	if ( ! file_exists( get_template_directory() . $relative ) ) {
		return '';
	}

	wp_enqueue_style(
		'refungi-bridge-stylesheet',
		get_template_directory_uri() . $relative,
		array( 'refungi-parent-style' ),
		$version
	);

	return 'refungi-bridge-stylesheet';
}

/**
 * Find a registered stylesheet whose URL ends with $relative.
 *
 * @param string $relative Path suffix such as /css/stylesheet.min.css.
 * @return string
 */
function refungi_child_find_style_handle( $relative ) {
	if ( ! isset( $GLOBALS['wp_styles'] ) || ! ( $GLOBALS['wp_styles'] instanceof WP_Styles ) ) {
		return '';
	}

	$length = strlen( $relative );
	foreach ( $GLOBALS['wp_styles']->registered as $handle => $style ) {
		if ( ! isset( $style->src ) || ! is_string( $style->src ) ) {
			continue;
		}
		if ( strlen( $style->src ) >= $length && substr( $style->src, -$length ) === $relative ) {
			return (string) $handle;
		}
	}

	return '';
}
