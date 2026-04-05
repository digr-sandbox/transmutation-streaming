<?php
/**
 * Main WordPress API
 *
 * @package WordPress
 */

// Don't load directly.
if ( ! defined( 'ABSPATH' ) ) {
	die( '-1' );
}

require ABSPATH . WPINC . '/option.php';

/**
 * Converts given MySQL date string into a different format.
 *
 *  - `$format` should be a PHP date format string.
 *  - 'U' and 'G' formats will return an integer sum of timestamp with timezone offset.
 *  - `$date` is expected to be local time in MySQL format (`Y-m-d H:i:s`).
 *
 * Historically UTC time could be passed to the function to produce Unix timestamp.
 *
 * If `$translate` is true then the given date and format string will
 * be passed to `wp_date()` for translation.
 *
 * @since 0.71
 *
 * @param string $format    Format of the date to return.
 * @param string $date      Date string to convert.
 * @param bool   $translate Whether the return date should be translated. Default true.
 * @return string|int|false Integer if `$format` is 'U' or 'G', string otherwise.
 *                          False on failure.
 */
function mysql2date( $format, $date, $translate = true ) {
	if ( empty( $date ) ) {
		return false;
	}

	$timezone = wp_timezone();
	$datetime = date_create( $date, $timezone );

	if ( false === $datetime ) {
		return false;
	}

	// Returns a sum of timestamp with timezone offset. Ideally should never be used.
	if ( 'G' === $format || 'U' === $format ) {
		return $datetime->getTimestamp() + $datetime->getOffset();
	}

	if ( $translate ) {
		return wp_date( $format, $datetime->getTimestamp(), $timezone );
	}

	return $datetime->format( $format );
}

/**
 * Retrieves the current time based on specified type.
 *
 *  - The 'mysql' type will return the time in the format for MySQL DATETIME field.
 *  - The 'timestamp' or 'U' types will return the current timestamp or a sum of timestamp
 *    and timezone offset, depending on `$gmt`.
 *  - Other strings will be interpreted as PHP date formats (e.g. 'Y-m-d').
 *
 * If `$gmt` is a truthy value then both types will use GMT time, otherwise the
 * output is adjusted with the GMT offset for the site.
 *
 * @since 1.0.0
 * @since 5.3.0 Now returns an integer if `$type` is 'U'. Previously a string was returned.
 *
 * @param string $type Type of time to retrieve. Accepts 'mysql', 'timestamp', 'U',
 *                     or PHP date format string (e.g. 'Y-m-d').
 * @param bool   $gmt  Optional. Whether to use GMT timezone. Default false.
 * @return int|string Integer if `$type` is 'timestamp' or 'U', string otherwise.
 */
function current_time( $type, $gmt = false ) {
	// Don't use non-GMT timestamp, unless you know the difference and really need to.
	if ( 'timestamp' === $type || 'U' === $type ) {
		return $gmt ? time() : time() + (int) ( (float) get_option( 'gmt_offset' ) * HOUR_IN_SECONDS );
	}

	if ( 'mysql' === $type ) {
		$type = 'Y-m-d H:i:s';
	}

	$timezone = $gmt ? new DateTimeZone( 'UTC' ) : wp_timezone();
	$datetime = new DateTime( 'now', $timezone );

	return $datetime->format( $type );
}

/**
 * Retrieves the current time as an object using the site's timezone.
 *
 * @since 5.3.0
 *
 * @return DateTimeImmutable Date and time object.
 */
function current_datetime() {
	return new DateTimeImmutable( 'now', wp_timezone() );
}

/**
 * Retrieves the timezone of the site as a string.
 *
 * Uses the `timezone_string` option to get a proper timezone name if available,
 * otherwise falls back to a manual UTC Â± offset.
 *
 * Example return values:
 *
 *  - 'Europe/Rome'
 *  - 'America/North_Dakota/New_Salem'
 *  - 'UTC'
 *  - '-06:30'
 *  - '+00:00'
 *  - '+08:45'
 *
 * @since 5.3.0
 *
 * @return string PHP timezone name or a Â±HH:MM offset.
 */
function wp_timezone_string() {
	$timezone_string = get_option( 'timezone_string' );

	if ( $timezone_string ) {
		return $timezone_string;
	}

	$offset  = (float) get_option( 'gmt_offset' );
	$hours   = (int) $offset;
	$minutes = ( $offset - $hours );

	$sign      = ( $offset < 0 ) ? '-' : '+';
	$abs_hour  = abs( $hours );
	$abs_mins  = abs( $minutes * 60 );
	$tz_offset = sprintf( '%s%02d:%02d', $sign, $abs_hour, $abs_mins );

	return $tz_offset;
}

/**
 * Retrieves the timezone of the site as a `DateTimeZone` object.
 *
 * Timezone can be based on a PHP timezone string or a Â±HH:MM offset.
 *
 * @since 5.3.0
 *
 * @return DateTimeZone Timezone object.
 */
function wp_timezone() {
	return new DateTimeZone( wp_timezone_string() );
}

/**
 * Retrieves the date in localized format, based on a sum of Unix timestamp and
 * timezone offset in seconds.
 *
 * If the locale specifies the locale month and weekday, then the locale will
 * take over the format for the date. If it isn't, then the date format string
 * will be used instead.
 *
 * Note that due to the way WP typically generates a sum of timestamp and offset
 * with `strtotime()`, it implies offset added at a _current_ time, not at the time
 * the timestamp represents. Storing such timestamps or calculating them differently
 * will lead to invalid output.
 *
 * @since 0.71
 * @since 5.3.0 Converted into a wrapper for wp_date().
 *
 * @param string   $format                Format to display the date.
 * @param int|bool $timestamp_with_offset Optional. A sum of Unix timestamp and timezone offset
 *                                        in seconds. Default false.
 * @param bool     $gmt                   Optional. Whether to use GMT timezone. Only applies
 *                                        if timestamp is not provided. Default false.
 * @return string The date, translated if locale specifies it.
 */
function date_i18n( $format, $timestamp_with_offset = false, $gmt = false ) {
	$timestamp = $timestamp_with_offset;

	// If timestamp is omitted it should be current time (summed with offset, unless `$gmt` is true).
	if ( ! is_numeric( $timestamp ) ) {
		// phpcs:ignore WordPress.DateTime.CurrentTimeTimestamp.Requested
		$timestamp = current_time( 'timestamp', $gmt );
	}

	/*
	 * This is a legacy implementation quirk that the returned timestamp is also with offset.
	 * Ideally this function should never be used to produce a timestamp.
	 */
	if ( 'U' === $format ) {
		$date = $timestamp;
	} elseif ( $gmt && false === $timestamp_with_offset ) { // Current time in UTC.
		$date = wp_date( $format, null, new DateTimeZone( 'UTC' ) );
	} elseif ( false === $timestamp_with_offset ) { // Current time in site's timezone.
		$date = wp_date( $format );
	} else {
		/*
		 * Timestamp with offset is typically produced by a UTC `strtotime()` call on an input without timezone.
		 * This is the best attempt to reverse that operation into a local time to use.
		 */
		$local_time = gmdate( 'Y-m-d H:i:s', $timestamp );
		$timezone   = wp_timezone();
		$datetime   = date_create( $local_time, $timezone );
		$date       = wp_date( $format, $datetime->getTimestamp(), $timezone );
	}

	/**
	 * Filters the date formatted based on the locale.
	 *
	 * @since 2.8.0
	 *
	 * @param string $date      Formatted date string.
	 * @param string $format    Format to display the date.
	 * @param int    $timestamp A sum of Unix timestamp and timezone offset in seconds.
	 *                          Might be without offset if input omitted timestamp but requested GMT.
	 * @param bool   $gmt       Whether to use GMT timezone. Only applies if timestamp was not provided.
	 */
	$date = apply_filters( 'date_i18n', $date, $format, $timestamp, $gmt );

	return $date;
}

/**
 * Retrieves the date, in localized format.
 *
 * This is a newer function, intended to replace `date_i18n()` without legacy quirks in it.
 *
 * Note that, unlike `date_i18n()`, this function accepts a true Unix timestamp, not summed
 * with timezone offset.
 *
 * @since 5.3.0
 *
 * @global WP_Locale $wp_locale WordPress date and time locale object.
 *
 * @param string            $format    PHP date format.
 * @param int|null          $timestamp Optional. Unix timestamp. Defaults to current time.
 * @param DateTimeZone|null $timezone  Optional. Timezone to output result in. Defaults to timezone
 *                                     from site settings.
 * @return string|false The date, translated if locale specifies it. False on invalid timestamp input.
 */
function wp_date( $format, $timestamp = null, $timezone = null ) {
	global $wp_locale;

	if ( null === $timestamp ) {
		$timestamp = time();
	} elseif ( ! is_numeric( $timestamp ) ) {
		return false;
	}

	if ( ! $timezone ) {
		$timezone = wp_timezone();
	}

	$datetime = date_create( '@' . $timestamp );
	$datetime->setTimezone( $timezone );

	if ( empty( $wp_locale->month ) || empty( $wp_locale->weekday ) ) {
		$date = $datetime->format( $format );
	} else {
		// We need to unpack shorthand `r` format because it has parts that might be localized.
		$format = preg_replace( '/(?<!\\\\)r/', DATE_RFC2822, $format );

		$new_format    = '';
		$format_length = strlen( $format );
		$month         = $wp_locale->get_month( $datetime->format( 'm' ) );
		$weekday       = $wp_locale->get_weekday( $datetime->format( 'w' ) );

		for ( $i = 0; $i < $format_length; $i++ ) {
			switch ( $format[ $i ] ) {
				case 'D':
					$new_format .= addcslashes( $wp_locale->get_weekday_abbrev( $weekday ), '\\A..Za..z' );
					break;
				case 'F':
					$new_format .= addcslashes( $month, '\\A..Za..z' );
					break;
				case 'l':
					$new_format .= addcslashes( $weekday, '\\A..Za..z' );
					break;
				case 'M':
					$new_format .= addcslashes( $wp_locale->get_month_abbrev( $month ), '\\A..Za..z' );
					break;
				case 'a':
					$new_format .= addcslashes( $wp_locale->get_meridiem( $datetime->format( 'a' ) ), '\\A..Za..z' );
					break;
				case 'A':
					$new_format .= addcslashes( $wp_locale->get_meridiem( $datetime->format( 'A' ) ), '\\A..Za..z' );
					break;
				case '\\':
					$new_format .= $format[ $i ];

					// If character follows a slash, we add it without translating.
					if ( $i < $format_length ) {
						$new_format .= $format[ ++$i ];
					}
					break;
				default:
					$new_format .= $format[ $i ];
					break;
			}
		}

		$date = $datetime->format( $new_format );
		$date = wp_maybe_decline_date( $date, $format );
	}

	/**
	 * Filters the date formatted based on the locale.
	 *
	 * @since 5.3.0
	 *
	 * @param string       $date      Formatted date string.
	 * @param string       $format    Format to display the date.
	 * @param int          $timestamp Unix timestamp.
	 * @param DateTimeZone $timezone  Timezone.
	 */
	$date = apply_filters( 'wp_date', $date, $format, $timestamp, $timezone );

	return $date;
}

/**
 * Determines if the date should be declined.
 *
 * If the locale specifies that month names require a genitive case in certain
 * formats (like 'j F Y'), the month name will be replaced with a correct form.
 *
 * @since 4.4.0
 * @since 5.4.0 The `$format` parameter was added.
 *
 * @global WP_Locale $wp_locale WordPress date and time locale object.
 *
 * @param string $date   Formatted date string.
 * @param string $format Optional. Date format to check. Default empty string.
 * @return string The date, declined if locale specifies it.
 */
function wp_maybe_decline_date( $date, $format = '' ) {
	global $wp_locale;

	// i18n functions are not available in SHORTINIT mode.
	if ( ! function_exists( '_x' ) ) {
		return $date;
	}

	/*
	 * translators: If months in your language require a genitive case,
	 * translate this to 'on'. Do not translate into your own language.
	 */
	if ( 'on' === _x( 'off', 'decline months names: on or off' ) ) {

		$months          = $wp_locale->month;
		$months_genitive = $wp_locale->month_genitive;

		/*
		 * Match a format like 'j F Y' or 'j. F' (day of the month, followed by month name)
		 * and decline the month.
		 */
		if ( $format ) {
			$decline = preg_match( '#[dj]\.? F#', $format );
		} else {
			// If the format is not passed, try to guess it from the date string.
			$decline = preg_match( '#\b\d{1,2}\.? [^\d ]+\b#u', $date );
		}

		if ( $decline ) {
			foreach ( $months as $key => $month ) {
				$months[ $key ] = '# ' . preg_quote( $month, '#' ) . '\b#u';
			}

			foreach ( $months_genitive as $key => $month ) {
				$months_genitive[ $key ] = ' ' . $month;
			}

			$date = preg_replace( $months, $months_genitive, $date );
		}

		/*
		 * Match a format like 'F jS' or 'F j' (month name, followed by day with an optional ordinal suffix)
		 * and change it to declined 'j F'.
		 */
		if ( $format ) {
			$decline = preg_match( '#F [dj]#', $format );
		} else {
			// If the format is not passed, try to guess it from the date string.
			$decline = preg_match( '#\b[^\d ]+ \d{1,2}(st|nd|rd|th)?\b#u', trim( $date ) );
		}

		if ( $decline ) {
			foreach ( $months as $key => $month ) {
				$months[ $key ] = '#\b' . preg_quote( $month, '#' ) . ' (\d{1,2})(st|nd|rd|th)?([-â€“]\d{1,2})?(st|nd|rd|th)?\b#u';
			}

			foreach ( $months_genitive as $key => $month ) {
				$months_genitive[ $key ] = '$1$3 ' . $month;
			}

			$date = preg_replace( $months, $months_genitive, $date );
		}
	}

	// Used for locale-specific rules.
	$locale = get_locale();

	if ( 'ca' === $locale ) {
		// " de abril| de agost| de octubre..." -> " d'abril| d'agost| d'octubre..."
		$date = preg_replace( '# de ([ao])#i', " d'\\1", $date );
	}

	return $date;
}

/**
 * Converts float number to format based on the locale.
 *
 * @since 2.3.0
 *
 * @global WP_Locale $wp_locale WordPress date and time locale object.
 *
 * @param float $number   The number to convert based on locale.
 * @param int   $decimals Optional. Precision of the number of decimal places. Default 0.
 * @return string Converted number in string format.
 */
function number_format_i18n( $number, $decimals = 0 ) {
	global $wp_locale;

	if ( isset( $wp_locale ) ) {
		$formatted = number_format( $number, absint( $decimals ), $wp_locale->number_format['decimal_point'], $wp_locale->number_format['thousands_sep'] );
	} else {
		$formatted = number_format( $number, absint( $decimals ) );
	}

	/**
	 * Filters the number formatted based on the locale.
	 *
	 * @since 2.8.0
	 * @since 4.9.0 The `$number` and `$decimals` parameters were added.
	 *
	 * @param string $formatted Converted number in string format.
	 * @param float  $number    The number to convert based on locale.
	 * @param int    $decimals  Precision of the number of decimal places.
	 */
	return apply_filters( 'number_format_i18n', $formatted, $number, $decimals );
}

/**
 * Converts a number of bytes to the largest unit the bytes will fit into.
 *
 * It is easier to read 1 KB than 1024 bytes and 1 MB than 1048576 bytes. Converts
 * number of bytes to human readable number by taking the number of that unit
 * that the bytes will go into it. Supports YB value.
 *
 * Please note that integers in PHP are limited to 32 bits, unless they are on
 * 64 bit architecture, then they have 64 bit size. If you need to place the
 * larger size then what PHP integer type will hold, then use a string. It will
 * be converted to a double, which should always have 64 bit length.
 *
 * Technically the correct unit names for powers of 1024 are KiB, MiB etc.
 *
 * @since 2.3.0
 * @since 6.0.0 Support for PB, EB, ZB, and YB was added.
 *
 * @param int|string $bytes    Number of bytes. Note max integer size for integers.
 * @param int        $decimals Optional. Precision of number of decimal places. Default 0.
 * @return string|false Number string on success, false on failure.
 */
function size_format( $bytes, $decimals = 0 ) {
	$quant = array(
		/* translators: Unit symbol for yottabyte. */
		_x( 'YB', 'unit symbol' ) => YB_IN_BYTES,
		/* translators: Unit symbol for zettabyte. */
		_x( 'ZB', 'unit symbol' ) => ZB_IN_BYTES,
		/* translators: Unit symbol for exabyte. */
		_x( 'EB', 'unit symbol' ) => EB_IN_BYTES,
		/* translators: Unit symbol for petabyte. */
		_x( 'PB', 'unit symbol' ) => PB_IN_BYTES,
		/* translators: Unit symbol for terabyte. */
		_x( 'TB', 'unit symbol' ) => TB_IN_BYTES,
		/* translators: Unit symbol for gigabyte. */
		_x( 'GB', 'unit symbol' ) => GB_IN_BYTES,
		/* translators: Unit symbol for megabyte. */
		_x( 'MB', 'unit symbol' ) => MB_IN_BYTES,
		/* translators: Unit symbol for kilobyte. */
		_x( 'KB', 'unit symbol' ) => KB_IN_BYTES,
		/* translators: Unit symbol for byte. */
		_x( 'B', 'unit symbol' )  => 1,
	);

	if ( 0 === $bytes ) {
		/* translators: Unit symbol for byte. */
		return number_format_i18n( 0, $decimals ) . ' ' . _x( 'B', 'unit symbol' );
	}

	foreach ( $quant as $unit => $mag ) {
		if ( (float) $bytes >= $mag ) {
			return number_format_i18n( $bytes / $mag, $decimals ) . ' ' . $unit;
		}
	}

	return false;
}

/**
 * Converts a duration to human readable format.
 *
 * @since 5.1.0
 *
 * @param string $duration Duration will be in string format (HH:ii:ss) OR (ii:ss),
 *                         with a possible prepended negative sign (-).
 * @return string|false A human readable duration string, false on failure.
 */
function human_readable_duration( $duration = '' ) {
	if ( ( empty( $duration ) || ! is_string( $duration ) ) ) {
		return false;
	}

	$duration = trim( $duration );

	// Remove prepended negative sign.
	if ( str_starts_with( $duration, '-' ) ) {
		$duration = substr( $duration, 1 );
	}

	// Extract duration parts.
	$duration_parts = array_reverse( explode( ':', $duration ) );
	$duration_count = count( $duration_parts );

	$hour   = null;
	$minute = null;
	$second = null;

	if ( 3 === $duration_count ) {
		// Validate HH:ii:ss duration format.
		if ( ! ( (bool) preg_match( '/^([0-9]+):([0-5]?[0-9]):([0-5]?[0-9])$/', $duration ) ) ) {
			return false;
		}
		// Three parts: hours, minutes & seconds.
		list( $second, $minute, $hour ) = $duration_parts;
	} elseif ( 2 === $duration_count ) {
		// Validate ii:ss duration format.
		if ( ! ( (bool) preg_match( '/^([0-5]?[0-9]):([0-5]?[0-9])$/', $duration ) ) ) {
			return false;
		}
		// Two parts: minutes & seconds.
		list( $second, $minute ) = $duration_parts;
	} else {
		return false;
	}

	$human_readable_duration = array();

	// Add the hour part to the string.
	if ( is_numeric( $hour ) ) {
		/* translators: %s: Time duration in hour or hours. */
		$human_readable_duration[] = sprintf( _n( '%s hour', '%s hours', $hour ), (int) $hour );
	}

	// Add the minute part to the string.
	if ( is_numeric( $minute ) ) {
		/* translators: %s: Time duration in minute or minutes. */
		$human_readable_duration[] = sprintf( _n( '%s minute', '%s minutes', $minute ), (int) $minute );
	}

	// Add the second part to the string.
	if ( is_numeric( $second ) ) {
		/* translators: %s: Time duration in second or seconds. */
		$human_readable_duration[] = sprintf( _n( '%s second', '%s seconds', $second ), (int) $second );
	}

	return implode( ', ', $human_readable_duration );
}

/**
 * Gets the week start and end from the datetime or date string from MySQL.
 *
 * @since 0.71
 *
 * @param string     $mysqlstring   Date or datetime field type from MySQL.
 * @param int|string $start_of_week Optional. Start of the week as an integer. Default empty string.
 * @return int[] {
 *     Week start and end dates as Unix timestamps.
 *
 *     @type int $start The week start date as a Unix timestamp.
 *     @type int $end   The week end date as a Unix timestamp.
 * }
 */
function get_weekstartend( $mysqlstring, $start_of_week = '' ) {
	// MySQL string year.
	$my = substr( $mysqlstring, 0, 4 );

	// MySQL string month.
	$mm = substr( $mysqlstring, 8, 2 );

	// MySQL string day.
	$md = substr( $mysqlstring, 5, 2 );

	// The timestamp for MySQL string day.
	$day = mktime( 0, 0, 0, $md, $mm, $my );

	// The day of the week from the timestamp.
	$weekday = (int) gmdate( 'w', $day );

	if ( ! is_numeric( $start_of_week ) ) {
		$start_of_week = (int) get_option( 'start_of_week' );
	}

	if ( $weekday < $start_of_week ) {
		$weekday += 7;
	}

	// The most recent week start day on or before $day.
	$start = $day - DAY_IN_SECONDS * ( $weekday - $start_of_week );

	// $start + 1 week - 1 second.
	$end = $start + WEEK_IN_SECONDS - 1;

	return compact( 'start', 'end' );
}

/**
 * Serializes data, if needed.
 *
 * @since 2.0.5
 *
 * @param string|array|object $data Data that might be serialized.
 * @return mixed A scalar data.
 */
function maybe_serialize( $data ) {
	if ( is_array( $data ) || is_object( $data ) ) {
		return serialize( $data );
	}

	/*
	 * Double serialization is required for backward compatibility.
	 * See https://core.trac.wordpress.org/ticket/12930
	 * Also the world will end. See WP 3.6.1.
	 */
	if ( is_serialized( $data, false ) ) {
		return serialize( $data );
	}

	return $data;
}

/**
 * Unserializes data only if it was serialized.
 *
 * @since 2.0.0
 *
 * @param string $data Data that might be unserialized.
 * @return mixed Unserialized data can be any type.
 */
function maybe_unserialize( $data ) {
	if ( is_serialized( $data ) ) { // Don't attempt to unserialize data that wasn't serialized going in.
		return @unserialize( trim( $data ) );
	}

	return $data;
}

/**
 * Checks value to find if it was serialized.
 *
 * If $data is not a string, then returned value will always be false.
 * Serialized data is always a string.
 *
 * @since 2.0.5
 * @since 6.1.0 Added Enum support.
 *
 * @param string $data   Value to check to see if was serialized.
 * @param bool   $strict Optional. Whether to be strict about the end of the string. Default true.
 * @return bool False if not serialized and true if it was.
 */
function is_serialized( $data, $strict = true ) {
	// If it isn't a string, it isn't serialized.
	if ( ! is_string( $data ) ) {
		return false;
	}
	$data = trim( $data );
	if ( 'N;' === $data ) {
		return true;
	}
	if ( strlen( $data ) < 4 ) {
		return false;
	}
	if ( ':' !== $data[1] ) {
		return false;
	}
	if ( $strict ) {
		$lastc = substr( $data, -1 );
		if ( ';' !== $lastc && '}' !== $lastc ) {
			return false;
		}
	} else {
		$semicolon = strpos( $data, ';' );
		$brace     = strpos( $data, '}' );
		// Either ; or } must exist.
		if ( false === $semicolon && false === $brace ) {
			return false;
		}
		// But neither must be in the first X characters.
		if ( false !== $semicolon && $semicolon < 3 ) {
			return false;
		}
		if ( false !== $brace && $brace < 4 ) {
			return false;
		}
	}
	$token = $data[0];
	switch ( $token ) {
		case 's':
			if ( $strict ) {
				if ( '"' !== substr( $data, -2, 1 ) ) {
					return false;
				}
			} elseif ( ! str_contains( $data, '"' ) ) {
				return false;
			}
			// Or else fall through.
		case 'a':
		case 'O':
		case 'E':
			return (bool) preg_match( "/^{$token}:[0-9]+:/s", $data );
		case 'b':
		case 'i':
		case 'd':
			$end = $strict ? '$' : '';
			return (bool) preg_match( "/^{$token}:[0-9.E+-]+;$end/", $data );
	}
	return false;
}

/**
 * Checks whether serialized data is of string type.
 *
 * @since 2.0.5
 *
 * @param string $data Serialized data.
 * @return bool False if not a serialized string, true if it is.
 */
function is_serialized_string( $data ) {
	// if it isn't a string, it isn't a serialized string.
	if ( ! is_string( $data ) ) {
		return false;
	}
	$data = trim( $data );
	if ( strlen( $data ) < 4 ) {
		return false;
	} elseif ( ':' !== $data[1] ) {
		return false;
	} elseif ( ! str_ends_with( $data, ';' ) ) {
		return false;
	} elseif ( 's' !== $data[0] ) {
		return false;
	} elseif ( '"' !== substr( $data, -2, 1 ) ) {
		return false;
	} else {
		return true;
	}
}

/**
 * Retrieves post title from XML-RPC XML.
 *
 * If the `title` element is not found in the XML, the default post title
 * from the `$post_default_title` global will be used instead.
 *
 * @since 0.71
 *
 * @global string $post_default_title Default XML-RPC post title.
 *
 * @param string $content XML-RPC XML Request content.
 * @return string Post title.
 */
function xmlrpc_getposttitle( $content ) {
	global $post_default_title;
	if ( preg_match( '/<title>(.+?)<\/title>/is', $content, $matchtitle ) ) {
		$post_title = $matchtitle[1];
	} else {
		$post_title = $post_default_title;
	}
	return $post_title;
}

/**
 * Retrieves the post category or categories from XML-RPC XML.
 *
 * If the `category` element is not found in the XML, the default post category
 * from the `$post_default_category` global will be used instead.
 * The return type will then be a string.
 *
 * If the `category` element is found, the return type will be an array.
 *
 * @since 0.71
 *
 * @global string $post_default_category Default XML-RPC post category.
 *
 * @param string $content XML-RPC XML Request content.
 * @return string[]|string An array of category names or default category name.
 */
function xmlrpc_getpostcategory( $content ) {
	global $post_default_category;
	if ( preg_match( '/<category>(.+?)<\/category>/is', $content, $matchcat ) ) {
		$post_category = trim( $matchcat[1], ',' );
		$post_category = explode( ',', $post_category );
	} else {
		$post_category = $post_default_category;
	}
	return $post_category;
}

/**
 * XML-RPC XML content without title and category elements.
 *
 * @since 0.71
 *
 * @param string $content XML-RPC XML Request content.
 * @return string XML-RPC XML Request content without title and category elements.
 */
function xmlrpc_removepostdata( $content ) {
	$content = preg_replace( '/<title>(.+?)<\/title>/si', '', $content );
	$content = preg_replace( '/<category>(.+?)<\/category>/si', '', $content );
	$content = trim( $content );
	return $content;
}

/**
 * Uses RegEx to extract URLs from arbitrary content.
 *
 * @since 3.7.0
 * @since 6.0.0 Fixes support for HTML entities (Trac 30580).
 *
 * @param string $content Content to extract URLs from.
 * @return string[] Array of URLs found in passed string.
 */
function wp_extract_urls( $content ) {
	preg_match_all(
		"#([\"']?)("
			. '(?:([\w-]+:)?//?)'
			. '[^\s()<>]+'
			. '[.]'
			. '(?:'
				. '\([\w\d]+\)|'
				. '(?:'
					. "[^`!()\[\]{}:'\".,<>Â«Â»â€œâ€â€˜â€™\s]|"
					. '(?:[:]\d+)?/?'
				. ')+'
			. ')'
		. ")\\1#",
		$content,
		$post_links
	);

	$post_links = array_unique(
		array_map(
			static function ( $link ) {
				// Decode to replace valid entities, like &amp;.
				$link = html_entity_decode( $link );
				// Maintain backward compatibility by removing extraneous semi-colons (`;`).
				return str_replace( ';', '', $link );
			},
			$post_links[2]
		)
	);

	return array_values( $post_links );
}

/**
 * Checks content for video and audio links to add as enclosures.
 *
 * Will not add enclosures that have already been added and will
 * remove enclosures that are no longer in the post. This is called as
 * pingbacks and trackbacks.
 *
 * @since 1.5.0
 * @since 5.3.0 The `$content` parameter was made optional, and the `$post` parameter was
 *              updated to accept a post ID or a WP_Post object.
 * @since 5.6.0 The `$content` parameter is no longer optional, but passing `null` to skip it
 *              is still supported.
 *
 * @global wpdb $wpdb WordPress database abstraction object.
 *
 * @param string|null $content Post content. If `null`, the `post_content` field from `$post` is used.
 * @param int|WP_Post $post    Post ID or post object.
 * @return void|false Void on success, false if the post is not found.
 */
function do_enclose( $content, $post ) {
	global $wpdb;

	// @todo Tidy this code and make the debug code optional.
	require_once ABSPATH . WPINC . '/class-IXR.php';

	$post = get_post( $post );
	if ( ! $post ) {
		return false;
	}

	if ( null === $content ) {
		$content = $post->post_content;
	}

	$post_links = array();

	$pung = get_enclosed( $post->ID );

	$post_links_temp = wp_extract_urls( $content );

	foreach ( $pung as $link_test ) {
		// Link is no longer in post.
		if ( ! in_array( $link_test, $post_links_temp, true ) ) {
			$mids = $wpdb->get_col( $wpdb->prepare( "SELECT meta_id FROM $wpdb->postmeta WHERE post_id = %d AND meta_key = 'enclosure' AND meta_value LIKE %s", $post->ID, $wpdb->esc_like( $link_test ) . '%' ) );
			foreach ( $mids as $mid ) {
				delete_metadata_by_mid( 'post', $mid );
			}
		}
	}

	foreach ( (array) $post_links_temp as $link_test ) {
		// If we haven't pung it already.
		if ( ! in_array( $link_test, $pung, true ) ) {
			$test = parse_url( $link_test );
			if ( false === $test ) {
				continue;
			}
			if ( isset( $test['query'] ) ) {
				$post_links[] = $link_test;
			} elseif ( isset( $test['path'] ) && ( '/' !== $test['path'] ) && ( '' !== $test['path'] ) ) {
				$post_links[] = $link_test;
			}
		}
	}

	/**
	 * Filters the list of enclosure links before querying the database.
	 *
	 * Allows for the addition and/or removal of potential enclosures to save
	 * to postmeta before checking the database for existing enclosures.
	 *
	 * @since 4.4.0
	 *
	 * @param string[] $post_links An array of enclosure links.
	 * @param int      $post_id    Post ID.
	 */
	$post_links = apply_filters( 'enclosure_links', $post_links, $post->ID );

	foreach ( (array) $post_links as $url ) {
		$url = strip_fragment_from_url( $url );

		if ( '' !== $url && ! $wpdb->get_var( $wpdb->prepare( "SELECT post_id FROM $wpdb->postmeta WHERE post_id = %d AND meta_key = 'enclosure' AND meta_value LIKE %s", $post->ID, $wpdb->esc_like( $url ) . '%' ) ) ) {

			$headers = wp_get_http_headers( $url );
			if ( $headers ) {
				$len           = (int) ( $headers['Content-Length'] ?? 0 );
				$type          = $headers['Content-Type'] ?? '';
				$allowed_types = array( 'video', 'audio' );

				// Check to see if we can figure out the mime type from the extension.
				$url_parts = parse_url( $url );
				if ( false !== $url_parts && ! empty( $url_parts['path'] ) ) {
					$extension = pathinfo( $url_parts['path'], PATHINFO_EXTENSION );
					if ( ! empty( $extension ) ) {
						foreach ( wp_get_mime_types() as $exts => $mime ) {
							if ( preg_match( '!^(' . $exts . ')$!i', $extension ) ) {
								$type = $mime;
								break;
							}
						}
					}
				}

				if ( in_array( substr( $type, 0, strpos( $type, '/' ) ), $allowed_types, true ) ) {
					add_post_meta( $post->ID, 'enclosure', "$url\n$len\n$mime\n" );
				}
			}
		}
	}
}

/**
 * Retrieves HTTP Headers from URL.
 *
 * @since 1.5.1
 *
 * @param string $url        URL to retrieve HTTP headers from.
 * @param bool   $deprecated Not Used.
 * @return \WpOrg\Requests\Utility\CaseInsensitiveDictionary|false Headers on success, false on failure.
 */
function wp_get_http_headers( $url, $deprecated = false ) {
	if ( ! empty( $deprecated ) ) {
		_deprecated_argument( __FUNCTION__, '2.7.0' );
	}

	$response = wp_safe_remote_head( $url );

	if ( is_wp_error( $response ) ) {
		return false;
	}

	return wp_remote_retrieve_headers( $response );
}

/**
 * Determines whether the publish date of the current post in the loop is different
 * from the publish date of the previous post in the loop.
 *
 * For more information on this and similar theme functions, check out
 * the {@link https://developer.wordpress.org/themes/basics/conditional-tags/
 * Conditional Tags} article in the Theme Developer Handbook.
 *
 * @since 0.71
 *
 * @global string $currentday  The day of the current post in the loop.
 * @global string $previousday The day of the previous post in the loop.
 *
 * @return int 1 when new day, 0 if not a new day.
 */
function is_new_day() {
	global $currentday, $previousday;

	if ( $currentday !== $previousday ) {
		return 1;
	} else {
		return 0;
	}
}

/**
 * Builds a URL query based on an associative or indexed array.
 *
 * This is a convenient function for easily building URL queries.
 * It sets the separator to '&' and uses the _http_build_query() function.
 *
 * @since 2.3.0
 *
 * @see _http_build_query() Used to build the query
 * @link https://www.php.net/manual/en/function.http-build-query.php for more on what
 *       http_build_query() does.
 *
 * @param array $data URL-encode key/value pairs.
 * @return string URL-encoded string.
 */
function build_query( $data ) {
	return _http_build_query( $data, null, '&', '', false );
}

/**
 * From php.net (modified by Mark Jaquith to behave like the native PHP5 function).
 *
 * @since 3.2.0
 * @access private
 *
 * @see https://www.php.net/manual/en/function.http-build-query.php
 *
 * @param array|object $data      An array or object of data. Converted to array.
 * @param string       $prefix    Optional. Numeric index. If set, start parameter numbering with it.
 *                                Default null.
 * @param string       $sep       Optional. Argument separator; defaults to 'arg_separator.output'.
 *                                Default null.
 * @param string       $key       Optional. Used to prefix key name. Default empty string.
 * @param bool         $urlencode Optional. Whether to use urlencode() in the result. Default true.
 * @return string The query string.
 */
function _http_build_query( $data, $prefix = null, $sep = null, $key = '', $urlencode = true ) {
	$ret = array();

	foreach ( (array) $data as $k => $v ) {
		if ( $urlencode ) {
			$k = urlencode( $k );
		}

		if ( is_int( $k ) && null !== $prefix ) {
			$k = $prefix . $k;
		}

		if ( ! empty( $key ) ) {
			$k = $key . '%5B' . $k . '%5D';
		}

		if ( null === $v ) {
			continue;
		} elseif ( false === $v ) {
			$v = '0';
		}

		if ( is_array( $v ) || is_object( $v ) ) {
			array_push( $ret, _http_build_query( $v, '', $sep, $k, $urlencode ) );
		} elseif ( $urlencode ) {
			array_push( $ret, $k . '=' . urlencode( $v ) );
		} else {
			array_push( $ret, $k . '=' . $v );
		}
	}

	if ( null === $sep ) {
		$sep = ini_get( 'arg_separator.output' );
	}

	return implode( $sep, $ret );
}

/**
 * Retrieves a modified URL query string.
 *
 * You can rebuild the URL and append query variables to the URL query by using this function.
 * There are two ways to use this function; either a single key and value, or an associative array.
 *
 * Using a single key and value:
 *
 *     add_query_arg( 'key', 'value', 'http://example.com' );
 *
 * Using an associative array:
 *
 *     add_query_arg( array(
 *         'key1' => 'value1',
 *         'key2' => 'value2',
 *     ), 'http://example.com' );
 *
 * Omitting the URL from either use results in the current URL being used
 * (the value of `$_SERVER['REQUEST_URI']`).
 *
 * Values are expected to be encoded appropriately with urlencode() or rawurlencode().
 *
 * Setting any query variable's value to boolean false removes the key (see remove_query_arg()).
 *
 * Important: The return value of add_query_arg() is not escaped by default. Output should be
 * late-escaped with esc_url() or similar to help prevent vulnerability to cross-site scripting
 * (XSS) attacks.
 *
 * @since 1.5.0
 * @since 5.3.0 Formalized the existing and already documented parameters
 *              by adding `...$args` to the function signature.
 *
 * @param string|array $key   Either a query variable key, or an associative array of query variables.
 * @param string       $value Optional. Either a query variable value, or a URL to act upon.
 * @param string       $url   Optional. A URL to act upon.
 * @return string New URL query string (unescaped).
 */
function add_query_arg( ...$args ) {
	if ( is_array( $args[0] ) ) {
		if ( count( $args ) < 2 || false === $args[1] ) {
			$uri = $_SERVER['REQUEST_URI'];
		} else {
			$uri = $args[1];
		}
	} else {
		if ( count( $args ) < 3 || false === $args[2] ) {
			$uri = $_SERVER['REQUEST_URI'];
		} else {
			$uri = $args[2];
		}
	}

	$frag = strstr( $uri, '#' );
	if ( $frag ) {
		$uri = substr( $uri, 0, -strlen( $frag ) );
	} else {
		$frag = '';
	}

	if ( 0 === stripos( $uri, 'http://' ) ) {
		$protocol = 'http://';
		$uri      = substr( $uri, 7 );
	} elseif ( 0 === stripos( $uri, 'https://' ) ) {
		$protocol = 'https://';
		$uri      = substr( $uri, 8 );
	} else {
		$protocol = '';
	}

	if ( str_contains( $uri, '?' ) ) {
		list( $base, $query ) = explode( '?', $uri, 2 );
		$base                .= '?';
	} elseif ( $protocol || ! str_contains( $uri, '=' ) ) {
		$base  = $uri . '?';
		$query = '';
	} else {
		$base  = '';
		$query = $uri;
	}

	wp_parse_str( $query, $qs );
	$qs = urlencode_deep( $qs ); // This re-URL-encodes things that were already in the query string.
	if ( is_array( $args[0] ) ) {
		foreach ( $args[0] as $k => $v ) {
			$qs[ $k ] = $v;
		}
	} else {
		$qs[ $args[0] ] = $args[1];
	}

	foreach ( $qs as $k => $v ) {
		if ( false === $v ) {
			unset( $qs[ $k ] );
		}
	}

	$ret = build_query( $qs );
	$ret = trim( $ret, '?' );
	$ret = preg_replace( '#=(&|$)#', '$1', $ret );
	$ret = $protocol . $base . $ret . $frag;
	$ret = rtrim( $ret, '?' );
	$ret = str_replace( '?#', '#', $ret );
	return $ret;
}

/**
 * Removes an item or items from a query string.
 *
 * Important: The return value of remove_query_arg() is not escaped by default. Output should be
 * late-escaped with esc_url() or similar to help prevent vulnerability to cross-site scripting
 * (XSS) attacks.
 *
 * @since 1.5.0
 *
 * @param string|string[] $key   Query key or keys to remove.
 * @param false|string    $query Optional. When false uses the current URL. Default false.
 * @return string New URL query string.
 */
function remove_query_arg( $key, $query = false ) {
	if ( is_array( $key ) ) { // Removing multiple keys.
		foreach ( $key as $k ) {
			$query = add_query_arg( $k, false, $query );
		}
		return $query;
	}
	return add_query_arg( $key, false, $query );
}

/**
 * Returns an array of single-use query variable names that can be removed from a URL.
 *
 * @since 4.4.0
 *
 * @return string[] An array of query variable names to remove from the URL.
 */
function wp_removable_query_args() {
	$removable_query_args = array(
		'activate',
		'activated',
		'admin_email_remind_later',
		'approved',
		'core-major-auto-updates-saved',
		'deactivate',
		'delete_count',
		'deleted',
		'disabled',
		'doing_wp_cron',
		'enabled',
		'error',
		'hotkeys_highlight_first',
		'hotkeys_highlight_last',
		'ids',
		'locked',
		'message',
		'same',
		'saved',
		'settings-updated',
		'skipped',
		'spammed',
		'trashed',
		'unspammed',
		'untrashed',
		'update',
		'updated',
		'wp-post-new-reload',
	);

	/**
	 * Filters the list of query variable names to remove.
	 *
	 * @since 4.2.0
	 *
	 * @param string[] $removable_query_args An array of query variable names to remove from a URL.
	 */
	return apply_filters( 'removable_query_args', $removable_query_args );
}

/**
 * Walks the array while sanitizing the contents.
 *
 * @since 0.71
 * @since 5.5.0 Non-string values are left untouched.
 *
 * @param array $input_array Array to walk while sanitizing contents.
 * @return array Sanitized $input_array.
 */
function add_magic_quotes( $input_array ) {
	foreach ( (array) $input_array as $k => $v ) {
		if ( is_array( $v ) ) {
			$input_array[ $k ] = add_magic_quotes( $v );
		} elseif ( is_string( $v ) ) {
			$input_array[ $k ] = addslashes( $v );
		}
	}

	return $input_array;
}

/**
 * HTTP request for URI to retrieve content.
 *
 * @since 1.5.1
 *
 * @see wp_safe_remote_get()
 *
 * @param string $uri URI/URL of web page to retrieve.
 * @return string|false HTTP content. False on failure.
 */
function wp_remote_fopen( $uri ) {
	$parsed_url = parse_url( $uri );

	if ( ! $parsed_url || ! is_array( $parsed_url ) ) {
		return false;
	}

	$options            = array();
	$options['timeout'] = 10;

	$response = wp_safe_remote_get( $uri, $options );

	if ( is_wp_error( $response ) ) {
		return false;
	}

	return wp_remote_retrieve_body( $response );
}

/**
 * Sets up the WordPress query.
 *
 * @since 2.0.0
 *
 * @global WP       $wp           Current WordPress environment instance.
 * @global WP_Query $wp_query     WordPress Query object.
 * @global WP_Query $wp_the_query Copy of the WordPress Query object.
 *
 * @param string|array $query_vars Default WP_Query arguments.
 */
function wp( $query_vars = '' ) {
	global $wp, $wp_query, $wp_the_query;

	$wp->main( $query_vars );

	if ( ! isset( $wp_the_query ) ) {
		$wp_the_query = $wp_query;
	}
}

/**
 * Retrieves the description for the HTTP status.
 *
 * @since 2.3.0
 * @since 3.9.0 Added status codes 418, 428, 429, 431, and 511.
 * @since 4.5.0 Added status codes 308, 421, and 451.
 * @since 5.1.0 Added status code 103.
 * @since 6.6.0 Added status code 425.
 *
 * @global array $wp_header_to_desc
 *
 * @param int $code HTTP status code.
 * @return string Status description if found, an empty string otherwise.
 */
function get_status_header_desc( $code ) {
	global $wp_header_to_desc;

	$code = absint( $code );

	if ( ! isset( $wp_header_to_desc ) ) {
		$wp_header_to_desc = array(
			100 => 'Continue',
			101 => 'Switching Protocols',
			102 => 'Processing',
			103 => 'Early Hints',

			200 => 'OK',
			201 => 'Created',
			202 => 'Accepted',
			203 => 'Non-Authoritative Information',
			204 => 'No Content',
			205 => 'Reset Content',
			206 => 'Partial Content',
			207 => 'Multi-Status',
			226 => 'IM Used',

			300 => 'Multiple Choices',
			301 => 'Moved Permanently',
			302 => 'Found',
			303 => 'See Other',
			304 => 'Not Modified',
			305 => 'Use Proxy',
			306 => 'Reserved',
			307 => 'Temporary Redirect',
			308 => 'Permanent Redirect',

			400 => 'Bad Request',
			401 => 'Unauthorized',
			402 => 'Payment Required',
			403 => 'Forbidden',
			404 => 'Not Found',
			405 => 'Method Not Allowed',
			406 => 'Not Acceptable',
			407 => 'Proxy Authentication Required',
			408 => 'Request Timeout',
			409 => 'Conflict',
			410 => 'Gone',
			411 => 'Length Required',
			412 => 'Precondition Failed',
			413 => 'Request Entity Too Large',
			414 => 'Request-URI Too Long',
			415 => 'Unsupported Media Type',
			416 => 'Requested Range Not Satisfiable',
			417 => 'Expectation Failed',
			418 => 'I\'m a teapot',
			421 => 'Misdirected Request',
			422 => 'Unprocessable Entity',
			423 => 'Locked',
			424 => 'Failed Dependency',
			425 => 'Too Early',
			426 => 'Upgrade Required',
			428 => 'Precondition Required',
			429 => 'Too Many Requests',
			431 => 'Request Header Fields Too Large',
			451 => 'Unavailable For Legal Reasons',

			500 => 'Internal Server Error',
			501 => 'Not Implemented',
			502 => 'Bad Gateway',
			503 => 'Service Unavailable',
			504 => 'Gateway Timeout',
			505 => 'HTTP Version Not Supported',
			506 => 'Variant Also Negotiates',
			507 => 'Insufficient Storage',
			510 => 'Not Extended',
			511 => 'Network Authentication Required',
		);
	}

	if ( isset( $wp_header_to_desc[ $code ] ) ) {
		return $wp_header_to_desc[ $code ];
	} else {
		return '';
	}
}

/**
 * Sets HTTP status header.
 *
 * @since 2.0.0
 * @since 4.4.0 Added the `$description` parameter.
 *
 * @see get_status_header_desc()
 *
 * @param int    $code        HTTP status code.
 * @param string $description Optional. A custom description for the HTTP status.
 *                            Defaults to the result of get_status_header_desc() for the given code.
 */
function status_header( $code, $description = '' ) {
	if ( ! $description ) {
		$description = get_status_header_desc( $code );
	}

	if ( empty( $description ) ) {
		return;
	}

	$protocol      = wp_get_server_protocol();
	$status_header = "$protocol $code $description";
	if ( function_exists( 'apply_filters' ) ) {

		/**
		 * Filters an HTTP status header.
		 *
		 * @since 2.2.0
		 *
		 * @param string $status_header HTTP status header.
		 * @param int    $code          HTTP status code.
		 * @param string $description   Description for the status code.
		 * @param string $protocol      Server protocol.
		 */
		$status_header = apply_filters( 'status_header', $status_header, $code, $description, $protocol );
	}

	if ( ! headers_sent() ) {
		header( $status_header, true, $code );
	}
}

/**
 * Gets the HTTP header information to prevent caching.
 *
 * The several different headers cover the different ways cache prevention
 * is handled by different browsers or intermediate caches such as proxy servers.
 *
 * @since 2.8.0
 * @since 6.3.0 The `Cache-Control` header for logged in users now includes the
 *              `no-store` and `private` directives.
 * @since 6.8.0 The `Cache-Control` header now includes the `no-store` and `private`
 *              directives regardless of whether a user is logged in.
 *
 * @return array The associative array of header names and field values.
 */
function wp_get_nocache_headers() {
	$cache_control = 'no-cache, must-revalidate, max-age=0, no-store, private';

	$headers = array(
		'Expires'       => 'Wed, 11 Jan 1984 05:00:00 GMT',
		'Cache-Control' => $cache_control,
	);

	if ( function_exists( 'apply_filters' ) ) {
		/**
		 * Filters the cache-controlling HTTP headers that are used to prevent caching.
		 *
		 * @since 2.8.0
		 *
		 * @see wp_get_nocache_headers()
		 *
		 * @param array $headers Header names and field values.
		 */
		$headers = (array) apply_filters( 'nocache_headers', $headers );
	}
	$headers['Last-Modified'] = false;
	return $headers;
}

/**
 * Sets the HTTP headers to prevent caching for the different browsers.
 *
 * Different browsers support different nocache headers, so several
 * headers must be sent so that all of them get the point that no
 * caching should occur.
 *
 * @since 2.0.0
 *
 * @see wp_get_nocache_headers()
 */
function nocache_headers() {
	if ( headers_sent() ) {
		return;
	}

	$headers = wp_get_nocache_headers();

	unset( $headers['Last-Modified'] );

	header_remove( 'Last-Modified' );

	foreach ( $headers as $name => $field_value ) {
		header( "{$name}: {$field_value}" );
	}
}

/**
 * Sets the HTTP headers for caching for 10 days with JavaScript content type.
 *
 * @since 2.1.0
 */
function cache_javascript_headers() {
	$expires_offset = 10 * DAY_IN_SECONDS;

	header( 'Content-Type: text/javascript; charset=' . get_bloginfo( 'charset' ) );
	header( 'Vary: Accept-Encoding' ); // Handle proxies.
	header( 'Expires: ' . gmdate( 'D, d M Y H:i:s', time() + $expires_offset ) . ' GMT' );
}

/**
 * Retrieves the number of database queries during the WordPress execution.
 *
 * @since 2.0.0
 *
 * @global wpdb $wpdb WordPress database abstraction object.
 *
 * @return int Number of database queries.
 */
function get_num_queries() {
	global $wpdb;
	return $wpdb->num_queries;
}

/**
 * Determines whether input is yes or no.
 *
 * Must be 'y' to be true.
 *
 * @since 1.0.0
 *
 * @param string $yn Character string containing either 'y' (yes) or 'n' (no).
 * @return bool True if 'y', false on anything else.
 */
function bool_from_yn( $yn ) {
	return ( 'y' === strtolower( $yn ) );
}

/**
 * Loads the feed template from the use of an action hook.
 *
 * If the feed action does not have a hook, then the function will die with a
 * message telling the visitor that the feed is not valid.
 *
 * It is better to only have one hook for each feed.
 *
 * @since 2.1.0
 *
 * @global WP_Query $wp_query WordPress Query object.
 */
function do_feed() {
	global $wp_query;

	$feed = get_query_var( 'feed' );

	// Remove the pad, if present.
	$feed = preg_replace( '/^_+/', '', $feed );

	if ( '' === $feed || 'feed' === $feed ) {
		$feed = get_default_feed();
	}

	if ( ! has_action( "do_feed_{$feed}" ) ) {
		wp_die( __( '<strong>Error:</strong> This is not a valid feed template.' ), '', array( 'response' => 404 ) );
	}

	/**
	 * Fires once the given feed is loaded.
	 *
	 * The dynamic portion of the hook name, `$feed`, refers to the feed template name.
	 *
	 * Possible hook names include:
	 *
	 *  - `do_feed_atom`
	 *  - `do_feed_rdf`
	 *  - `do_feed_rss`
	 *  - `do_feed_rss2`
	 *
	 * @since 2.1.0
	 * @since 4.4.0 The `$feed` parameter was added.
	 *
	 * @param bool   $is_comment_feed Whether the feed is a comment feed.
	 * @param string $feed            The feed name.
	 */
	do_action( "do_feed_{$feed}", $wp_query->is_comment_feed, $feed );
}

/**
 * Loads the RDF RSS 0.91 Feed template.
 *
 * @since 2.1.0
 *
 * @see load_template()
 */
function do_feed_rdf() {
	load_template( ABSPATH . WPINC . '/feed-rdf.php' );
}

/**
 * Loads the RSS 1.0 Feed Template.
 *
 * @since 2.1.0
 *
 * @see load_template()
 */
function do_feed_rss() {
	load_template( ABSPATH . WPINC . '/feed-rss.php' );
}

/**
 * Loads either the RSS2 comment feed or the RSS2 posts feed.
 *
 * @since 2.1.0
 *
 * @see load_template()
 *
 * @param bool $for_comments True for the comment feed, false for normal feed.
 */
function do_feed_rss2( $for_comments ) {
	if ( $for_comments ) {
		load_template( ABSPATH . WPINC . '/feed-rss2-comments.php' );
	} else {
		load_template( ABSPATH . WPINC . '/feed-rss2.php' );
	}
}

/**
 * Loads either Atom comment feed or Atom posts feed.
 *
 * @since 2.1.0
 *
 * @see load_template()
 *
 * @param bool $for_comments True for the comment feed, false for normal feed.
 */
function do_feed_atom( $for_comments ) {
	if ( $for_comments ) {
		load_template( ABSPATH . WPINC . '/feed-atom-comments.php' );
	} else {
		load_template( ABSPATH . WPINC . '/feed-atom.php' );
	}
}

/**
 * Displays the default robots.txt file content.
 *
 * @since 2.1.0
 * @since 5.3.0 Remove the "Disallow: /" output if search engine visibility is
 *              discouraged in favor of robots meta HTML tag via wp_robots_no_robots()
 *              filter callback.
 */
function do_robots() {
	header( 'Content-Type: text/plain; charset=utf-8' );

	/**
	 * Fires when displaying the robots.txt file.
	 *
	 * @since 2.1.0
	 */
	do_action( 'do_robotstxt' );

	$output = "User-agent: *\n";
	$public = (bool) get_option( 'blog_public' );

	$site_url = parse_url( site_url() );
	$path     = ( ! empty( $site_url['path'] ) ) ? $site_url['path'] : '';
	$output  .= "Disallow: $path/wp-admin/\n";
	$output  .= "Allow: $path/wp-admin/admin-ajax.php\n";

	/**
	 * Filters the robots.txt output.
	 *
	 * @since 3.0.0
	 *
	 * @param string $output The robots.txt output.
	 * @param bool   $public Whether the site is considered "public".
	 */
	echo apply_filters( 'robots_txt', $output, $public );
}

/**
 * Displays the favicon.ico file content.
 *
 * @since 5.4.0
 */
function do_favicon() {
	/**
	 * Fires when serving the favicon.ico file.
	 *
	 * @since 5.4.0
	 */
	do_action( 'do_faviconico' );

	wp_redirect( get_site_icon_url( 32, includes_url( 'images/w-logo-blue-white-bg.png' ) ) );
	exit;
}

/**
 * Determines whether WordPress is already installed.
 *
 * The cache will be checked first. If you have a cache plugin, which saves
 * the cache values, then this will work. If you use the default WordPress
 * cache, and the database goes away, then you might have problems.
 *
 * Checks for the 'siteurl' option for whether WordPress is installed.
 *
 * For more information on this and similar theme functions, check out
 * the {@link https://developer.wordpress.org/themes/basics/conditional-tags/
 * Conditional Tags} article in the Theme Developer Handbook.
 *
 * @since 2.1.0
 *
 * @global wpdb $wpdb WordPress database abstraction object.
 *
 * @return bool Whether the site is already installed.
 */
function is_blog_installed() {
	global $wpdb;

	/*
	 * Check cache first. If options table goes away and we have true
	 * cached, oh well.
	 */
	if ( wp_cache_get( 'is_blog_installed' ) ) {
		return true;
	}

	$suppress = $wpdb->suppress_errors();

	if ( ! wp_installing() ) {
		$alloptions = wp_load_alloptions();
	}

	// If siteurl is not set to autoload, check it specifically.
	if ( ! isset( $alloptions['siteurl'] ) ) {
		$installed = $wpdb->get_var( "SELECT option_value FROM $wpdb->options WHERE option_name = 'siteurl'" );
	} else {
		$installed = $alloptions['siteurl'];
	}

	$wpdb->suppress_errors( $suppress );

	$installed = ! empty( $installed );
	wp_cache_set( 'is_blog_installed', $installed );

	if ( $installed ) {
		return true;
	}

	// If visiting repair.php, return true and let it take over.
	if ( defined( 'WP_REPAIRING' ) ) {
		return true;
	}

	$suppress = $wpdb->suppress_errors();

	/*
	 * Loop over the WP tables. If none exist, then scratch installation is allowed.
	 * If one or more exist, suggest table repair since we got here because the
	 * options table could not be accessed.
	 */
	$wp_tables = $wpdb->tables();
	foreach ( $wp_tables as $table ) {
		// The existence of custom user tables shouldn't suggest an unwise state or prevent a clean installation.
		if ( defined( 'CUSTOM_USER_TABLE' ) && CUSTOM_USER_TABLE === $table ) {
			continue;
		}

		if ( defined( 'CUSTOM_USER_META_TABLE' ) && CUSTOM_USER_META_TABLE === $table ) {
			continue;
		}

		$described_table = $wpdb->get_results( "DESCRIBE $table;" );
		if (
			( ! $described_table && empty( $wpdb->last_error ) ) ||
			( is_array( $described_table ) && 0 === count( $described_table ) )
		) {
			continue;
		}

		// One or more tables exist. This is not good.

		wp_load_translations_early();

		// Die with a DB error.
		$wpdb->error = sprintf(
			/* translators: %s: Database repair URL. */
			__( 'One or more database tables are unavailable. The database may need to be <a href="%s">repaired</a>.' ),
			'maint/repair.php?referrer=is_blog_installed'
		);

		dead_db();
	}

	$wpdb->suppress_errors( $suppress );

	wp_cache_set( 'is_blog_installed', false );

	return false;
}

/**
 * Retrieves URL with nonce added to URL query.
 *
 * @since 2.0.4
 *
 * @param string     $actionurl URL to add nonce action.
 * @param int|string $action    Optional. Nonce action name. Default -1.
 * @param string     $name      Optional. Nonce name. Default '_wpnonce'.
 * @return string Escaped URL with nonce action added.
 */
function wp_nonce_url( $actionurl, $action = -1, $name = '_wpnonce' ) {
	$actionurl = str_replace( '&amp;', '&', $actionurl );
	return esc_html( add_query_arg( $name, wp_create_nonce( $action ), $actionurl ) );
}

/**
 * Retrieves or display nonce hidden field for forms.
 *
 * The nonce field is used to validate that the contents of the form came from
 * the location on the current site and not somewhere else. The nonce does not
 * offer absolute protection, but should protect against most cases. It is very
 * important to use nonce field in forms.
 *
 * The $action and $name are optional, but if you want to have better security,
 * it is strongly suggested to set those two parameters. It is easier to just
 * call the function without any parameters, because validation of the nonce
 * doesn't require any parameters, but since crackers know what the default is
 * it won't be difficult for them to find a way around your nonce and cause
 * damage.
 *
 * The input name will be whatever $name value you gave. The input value will be
 * the nonce creation value.
 *
 * @since 2.0.4
 *
 * @param int|string $action  Optional. Action name. Default -1.
 * @param string     $name    Optional. Nonce name. Default '_wpnonce'.
 * @param bool       $referer Optional. Whether to set the referer field for validation. Default true.
 * @param bool       $display Optional. Whether to display or return hidden form field. Default true.
 * @return string Nonce field HTML markup.
 */
function wp_nonce_field( $action = -1, $name = '_wpnonce', $referer = true, $display = true ) {
	$name        = esc_attr( $name );
	$nonce_field = '<input type="hidden" id="' . $name . '" name="' . $name . '" value="' . wp_create_nonce( $action ) . '" />';

	if ( $referer ) {
		$nonce_field .= wp_referer_field( false );
	}

	if ( $display ) {
		echo $nonce_field;
	}

	return $nonce_field;
}

/**
 * Retrieves or displays referer hidden field for forms.
 *
 * The referer link is the current Request URI from the server super global. The
 * input name is '_wp_http_referer', in case you wanted to check manually.
 *
 * @since 2.0.4
 *
 * @param bool $display Optional. Whether to echo or return the referer field. Default true.
 * @return string Referer field HTML markup.
 */
function wp_referer_field( $display = true ) {
	$request_url   = remove_query_arg( '_wp_http_referer' );
	$referer_field = '<input type="hidden" name="_wp_http_referer" value="' . esc_url( $request_url ) . '" />';

	if ( $display ) {
		echo $referer_field;
	}

	return $referer_field;
}

/**
 * Retrieves or displays original referer hidden field for forms.
 *
 * The input name is '_wp_original_http_referer' and will be either the same
 * value of wp_referer_field(), if that was posted already or it will be the
 * current page, if it doesn't exist.
 *
 * @since 2.0.4
 *
 * @param bool   $display      Optional. Whether to echo the original http referer. Default true.
 * @param string $jump_back_to Optional. Can be 'previous' or page you want to jump back to.
 *                             Default 'current'.
 * @return string Original referer field.
 */
function wp_original_referer_field( $display = true, $jump_back_to = 'current' ) {
	$ref = wp_get_original_referer();

	if ( ! $ref ) {
		$ref = ( 'previous' === $jump_back_to ) ? wp_get_referer() : wp_unslash( $_SERVER['REQUEST_URI'] );
	}

	$orig_referer_field = '<input type="hidden" name="_wp_original_http_referer" value="' . esc_attr( $ref ) . '" />';

	if ( $display ) {
		echo $orig_referer_field;
	}

	return $orig_referer_field;
}

/**
 * Retrieves referer from '_wp_http_referer' or HTTP referer.
 *
 * If it's the same as the current request URL, will return false.
 *
 * @since 2.0.4
 *
 * @return string|false Referer URL on success, false on failure.
 */
function wp_get_referer() {
	// Return early if called before wp_validate_redirect() is defined.
	if ( ! function_exists( 'wp_validate_redirect' ) ) {
		return false;
	}

	$ref = wp_get_raw_referer();

	if ( $ref && wp_unslash( $_SERVER['REQUEST_URI'] ) !== $ref
		&& home_url() . wp_unslash( $_SERVER['REQUEST_URI'] ) !== $ref
	) {
		return wp_validate_redirect( $ref, false );
	}

	return false;
}

/**
 * Retrieves unvalidated referer from the '_wp_http_referer' URL query variable or the HTTP referer.
 *
 * If the value of the '_wp_http_referer' URL query variable is not a string then it will be ignored.
 *
 * Do not use for redirects, use wp_get_referer() instead.
 *
 * @since 4.5.0
 *
 * @return string|false Referer URL on success, false on failure.
 */
function wp_get_raw_referer() {
	if ( ! empty( $_REQUEST['_wp_http_referer'] ) && is_string( $_REQUEST['_wp_http_referer'] ) ) {
		return wp_unslash( $_REQUEST['_wp_http_referer'] );
	} elseif ( ! empty( $_SERVER['HTTP_REFERER'] ) ) {
		return wp_unslash( $_SERVER['HTTP_REFERER'] );
	}

	return false;
}

/**
 * Retrieves original referer that was posted, if it exists.
 *
 * @since 2.0.4
 *
 * @return string|false Original referer URL on success, false on failure.
 */
function wp_get_original_referer() {
	// Return early if called before wp_validate_redirect() is defined.
	if ( ! function_exists( 'wp_validate_redirect' ) ) {
		return false;
	}

	if ( ! empty( $_REQUEST['_wp_original_http_referer'] ) ) {
		return wp_validate_redirect( wp_unslash( $_REQUEST['_wp_original_http_referer'] ), false );
	}

	return false;
}

/**
 * Recursive directory creation based on full path.
 *
 * Will attempt to set permissions on folders.
 *
 * @since 2.0.1
 *
 * @param string $target Full path to attempt to create.
 * @return bool Whether the path was created. True if path already exists.
 */
function wp_mkdir_p( $target ) {
	$wrapper = null;

	// Strip the protocol.
	if ( wp_is_stream( $target ) ) {
		list( $wrapper, $target ) = explode( '://', $target, 2 );
	}

	// From php.net/mkdir user contributed notes.
	$target = str_replace( '//', '/', $target );

	// Put the wrapper back on the target.
	if ( null !== $wrapper ) {
		$target = $wrapper . '://' . $target;
	}

	/*
	 * Safe mode fails with a trailing slash under certain PHP versions.
	 * Use rtrim() instead of untrailingslashit to avoid formatting.php dependency.
	 */
	$target = rtrim( $target, '/' );
	if ( empty( $target ) ) {
		$target = '/';
	}

	if ( file_exists( $target ) ) {
		return @is_dir( $target );
	}

	// Do not allow path traversals.
	if ( str_contains( $target, '../' ) || str_contains( $target, '..' . DIRECTORY_SEPARATOR ) ) {
		return false;
	}

	// We need to find the permissions of the parent folder that exists and inherit that.
	$target_parent = dirname( $target );
	while ( '.' !== $target_parent && ! is_dir( $target_parent ) && dirname( $target_parent ) !== $target_parent ) {
		$target_parent = dirname( $target_parent );
	}

	// Get the permission bits.
	$stat = @stat( $target_parent );
	if ( $stat ) {
		$dir_perms = $stat['mode'] & 0007777;
	} else {
		$dir_perms = 0777;
	}

	if ( @mkdir( $target, $dir_perms, true ) ) {

		/*
		 * If a umask is set that modifies $dir_perms, we'll have to re-set
		 * the $dir_perms correctly with chmod()
		 */
		if ( ( $dir_perms & ~umask() ) !== $dir_perms ) {
			$folder_parts = explode( '/', substr( $target, strlen( $target_parent ) + 1 ) );
			for ( $i = 1, $c = count( $folder_parts ); $i <= $c; $i++ ) {
				chmod( $target_parent . '/' . implode( '/', array_slice( $folder_parts, 0, $i ) ), $dir_perms );
			}
		}

		return true;
	}

	return false;
}

/**
 * Tests if a given filesystem path is absolute.
 *
 * For example, '/foo/bar', or 'c:\windows'.
 *
 * @since 2.5.0
 *
 * @param string $path File path.
 * @return bool True if path is absolute, false is not absolute.
 */
function path_is_absolute( $path ) {
	/*
	 * Check to see if the path is a stream and check to see if its an actual
	 * path or file as realpath() does not support stream wrappers.
	 */
	if ( wp_is_stream( $path ) && ( is_dir( $path ) || is_file( $path ) ) ) {
		return true;
	}

	/*
	 * This is definitive if true but fails if $path does not exist or contains
	 * a symbolic link.
	 */
	if ( realpath( $path ) === $path ) {
		return true;
	}

	if ( strlen( $path ) === 0 || '.' === $path[0] ) {
		return false;
	}

	// Windows allows absolute paths like this.
	if ( preg_match( '#^[a-zA-Z]:\\\\#', $path ) ) {
		return true;
	}

	// A path starting with / or \ is absolute; anything else is relative.
	return ( '/' === $path[0] || '\\' === $path[0] );
}

/**
 * Joins two filesystem paths together.
 *
 * For example, 'give me $path relative to $base'. If the $path is absolute,
 * then it the full path is returned.
 *
 * @since 2.5.0
 *
 * @param string $base Base path.
 * @param string $path Path relative to $base.
 * @return string The path with the base or absolute path.
 */
function path_join( $base, $path ) {
	if ( path_is_absolute( $path ) ) {
		return $path;
	}

	return rtrim( $base, '/' ) . '/' . $path;
}

/**
 * Normalizes a filesystem path.
 *
 * On windows systems, replaces backslashes with forward slashes
 * and forces upper-case drive letters.
 * Allows for two leading slashes for Windows network shares, but
 * ensures that all other duplicate slashes are reduced to a single.
 *
 * @since 3.9.0
 * @since 4.4.0 Ensures upper-case drive letters on Windows systems.
 * @since 4.5.0 Allows for Windows network shares.
 * @since 4.9.7 Allows for PHP file wrappers.
 * @since 7.0.0 Uses a static cache to store normalized paths.
 *
 * @param string $path Path to normalize.
 * @return string Normalized path.
 */
function wp_normalize_path( $path ): string {
	$path = (string) $path;

	static $cache = array();
	if ( isset( $cache[ $path ] ) ) {
		return $cache[ $path ];
	}

	$original_path = $path;
	$wrapper       = '';

	if ( wp_is_stream( $path ) ) {
		list( $wrapper, $path ) = explode( '://', $path, 2 );

		$wrapper .= '://';
	}

	// Standardize all paths to use '/'.
	$path = str_replace( '\\', '/', $path );

	// Replace multiple slashes down to a singular, allowing for network shares having two slashes.
	$path = (string) preg_replace( '|(?<=.)/+|', '/', $path );

	// Windows paths should uppercase the drive letter.
	if ( ':' === substr( $path, 1, 1 ) ) {
		$path = ucfirst( $path );
	}

	$cache[ $original_path ] = $wrapper . $path;
	return $cache[ $original_path ];
}

/**
 * Determines a writable directory for temporary files.
 *
 * Function's preference is the return value of `sys_get_temp_dir()`,
 * followed by the `upload_tmp_dir` value from `php.ini`, followed by `WP_CONTENT_DIR`,
 * before finally defaulting to `/tmp/`.
 *
 * Note that `sys_get_temp_dir()` honors the `TMPDIR` environment variable.
 *
 * In the event that this function does not find a writable location,
 * it may be overridden by the `WP_TEMP_DIR` constant in your `wp-config.php` file.
 *
 * @since 2.5.0
 *
 * @return string Writable temporary directory.
 */
function get_temp_dir() {
	static $temp = '';
	if ( defined( 'WP_TEMP_DIR' ) ) {
		return trailingslashit( WP_TEMP_DIR );
	}

	if ( $temp ) {
		return trailingslashit( $temp );
	}

	if ( function_exists( 'sys_get_temp_dir' ) ) {
		$temp = sys_get_temp_dir();
		if ( @is_dir( $temp ) && wp_is_writable( $temp ) ) {
			return trailingslashit( $temp );
		}
	}

	$temp = ini_get( 'upload_tmp_dir' );
	if ( @is_dir( $temp ) && wp_is_writable( $temp ) ) {
		return trailingslashit( $temp );
	}

	$temp = WP_CONTENT_DIR . '/';
	if ( is_dir( $temp ) && wp_is_writable( $temp ) ) {
		return $temp;
	}

	return '/tmp/';
}

/**
 * Determines if a directory is writable.
 *
 * This function is used to work around certain ACL issues in PHP primarily
 * affecting Windows Servers.
 *
 * @since 3.6.0
 *
 * @see win_is_writable()
 *
 * @param string $path Path to check for write-ability.
 * @return bool Whether the path is writable.
 */
function wp_is_writable( $path ) {
	if ( 'Windows' === PHP_OS_FAMILY ) {
		return win_is_writable( $path );
	}

	return @is_writable( $path );
}

/**
 * Workaround for Windows bug in is_writable() function
 *
 * PHP has issues with Windows ACL's for determine if a
 * directory is writable or not, this works around them by
 * checking the ability to open files rather than relying
 * upon PHP to interpret the OS ACL.
 *
 * @since 2.8.0
 *
 * @see https://bugs.php.net/bug.php?id=27609
 * @see https://bugs.php.net/bug.php?id=30931
 *
 * @param string $path Windows path to check for write-ability.
 * @return bool Whether the path is writable.
 */
function win_is_writable( $path ) {
	if ( '/' === $path[ strlen( $path ) - 1 ] ) {
		// If it looks like a directory, check a random file within the directory.
		return win_is_writable( $path . uniqid( mt_rand() ) . '.tmp' );
	} elseif ( is_dir( $path ) ) {
		// If it's a directory (and not a file), check a random file within the directory.
		return win_is_writable( $path . '/' . uniqid( mt_rand() ) . '.tmp' );
	}

	// Check tmp file for read/write capabilities.
	$should_delete_tmp_file = ! file_exists( $path );

	$f = @fopen( $path, 'a' );
	if ( false === $f ) {
		return false;
	}
	fclose( $f );

	if ( $should_delete_tmp_file ) {
		unlink( $path );
	}

	return true;
}

/**
 * Retrieves uploads directory information.
 *
 * Same as wp_upload_dir() but "light weight" as it doesn't attempt to create the uploads directory.
 * Intended for use in themes, when only 'basedir' and 'baseurl' are needed, generally in all cases
 * when not uploading files.
 *
 * @since 4.5.0
 *
 * @see wp_upload_dir()
 *
 * @return array See wp_upload_dir() for description.
 */
function wp_get_upload_dir() {
	return wp_upload_dir( null, false );
}

/**
 * Returns an array containing the current upload directory's path and URL.
 *
 * Checks the 'upload_path' option, which should be from the web root folder,
 * and if it isn't empty it will be used. If it is empty, then the path will be
 * 'WP_CONTENT_DIR/uploads'. If the 'UPLOADS' constant is defined, then it will
 * override the 'upload_path' option and 'WP_CONTENT_DIR/uploads' path.
 *
 * The upload URL path is set either by the 'upload_url_path' option or by using
 * the 'WP_CONTENT_URL' constant and appending '/uploads' to the path.
 *
 * If the 'uploads_use_yearmonth_folders' is set to true (checkbox if checked in
 * the administration settings panel), then the time will be used. The format
 * will be year first and then month.
 *
 * If the path couldn't be created, then an error will be returned with the key
 * 'error' containing the error message. The error suggests that the parent
 * directory is not writable by the server.
 *
 * @since 2.0.0
 * @uses _wp_upload_dir()
 *
 * @param string|null $time          Optional. Time formatted in 'yyyy/mm'. Default null.
 * @param bool        $create_dir    Optional. Whether to check and create the uploads directory.
 *                                   Default true for backward compatibility.
 * @param bool        $refresh_cache Optional. Whether to refresh the cache. Default false.
 * @return array {
 *     Array of information about the upload directory.
 *
 *     @type string       $path    Base directory and subdirectory or full path to upload directory.
 *     @type string       $url     Base URL and subdirectory or absolute URL to upload directory.
 *     @type string       $subdir  Subdirectory if uploads use year/month folders option is on.
 *     @type string       $basedir Path without subdir.
 *     @type string       $baseurl URL path without subdir.
 *     @type string|false $error   False or error message.
 * }
 */
function wp_upload_dir( $time = null, $create_dir = true, $refresh_cache = false ) {
	static $cache = array(), $tested_paths = array();

	$key = sprintf( '%d-%s', get_current_blog_id(), (string) $time );

	if ( $refresh_cache || empty( $cache[ $key ] ) ) {
		$cache[ $key ] = _wp_upload_dir( $time );
	}

	/**
	 * Filters the uploads directory data.
	 *
	 * @since 2.0.0
	 *
	 * @param array $uploads {
	 *     Array of information about the upload directory.
	 *
	 *     @type string       $path    Base directory and subdirectory or full path to upload directory.
	 *     @type string       $url     Base URL and subdirectory or absolute URL to upload directory.
	 *     @type string       $subdir  Subdirectory if uploads use year/month folders option is on.
	 *     @type string       $basedir Path without subdir.
	 *     @type string       $baseurl URL path without subdir.
	 *     @type string|false $error   False or error message.
	 * }
	 */
	$uploads = apply_filters( 'upload_dir', $cache[ $key ] );

	if ( $create_dir ) {
		$path = $uploads['path'];

		if ( array_key_exists( $path, $tested_paths ) ) {
			$uploads['error'] = $tested_paths[ $path ];
		} else {
			if ( ! wp_mkdir_p( $path ) ) {
				if ( str_starts_with( $uploads['basedir'], ABSPATH ) ) {
					$error_path = str_replace( ABSPATH, '', $uploads['basedir'] ) . $uploads['subdir'];
				} else {
					$error_path = wp_basename( $uploads['basedir'] ) . $uploads['subdir'];
				}

				$uploads['error'] = sprintf(
					/* translators: %s: Directory path. */
					__( 'Unable to create directory %s. Is its parent directory writable by the server?' ),
					esc_html( $error_path )
				);
			}

			$tested_paths[ $path ] = $uploads['error'];
		}
	}

	return $uploads;
}

/**
 * A non-filtered, non-cached version of wp_upload_dir() that doesn't check the path.
 *
 * @since 4.5.0
 * @access private
 *
 * @param string|null $time Optional. Time formatted in 'yyyy/mm'. Default null.
 * @return array See wp_upload_dir()
 */
function _wp_upload_dir( $time = null ) {
	$siteurl     = get_option( 'siteurl' );
	$upload_path = trim( get_option( 'upload_path' ) );

	if ( empty( $upload_path ) || 'wp-content/uploads' === $upload_path ) {
		$dir = WP_CONTENT_DIR . '/uploads';
	} elseif ( ! str_starts_with( $upload_path, ABSPATH ) ) {
		// $dir is absolute, $upload_path is (maybe) relative to ABSPATH.
		$dir = path_join( ABSPATH, $upload_path );
	} else {
		$dir = $upload_path;
	}

	$url = get_option( 'upload_url_path' );
	if ( ! $url ) {
		if ( empty( $upload_path ) || ( 'wp-content/uploads' === $upload_path ) || ( $upload_path === $dir ) ) {
			$url = WP_CONTENT_URL . '/uploads';
		} else {
			$url = trailingslashit( $siteurl ) . $upload_path;
		}
	}

	/*
	 * Honor the value of UPLOADS. This happens as long as ms-files rewriting is disabled.
	 * We also sometimes obey UPLOADS when rewriting is enabled -- see the next block.
	 */
	if ( defined( 'UPLOADS' ) && ! ( is_multisite() && get_site_option( 'ms_files_rewriting' ) ) ) {
		$dir = ABSPATH . UPLOADS;
		$url = trailingslashit( $siteurl ) . UPLOADS;
	}

	// If multisite (and if not the main site in a post-MU network).
	if ( is_multisite() && ! ( is_main_network() && is_main_site() && defined( 'MULTISITE' ) ) ) {

		if ( ! get_site_option( 'ms_files_rewriting' ) ) {
			/*
			 * If ms-files rewriting is disabled (networks created post-3.5), it is fairly
			 * straightforward: Append sites/%d if we're not on the main site (for post-MU
			 * networks). (The extra directory prevents a four-digit ID from conflicting with
			 * a year-based directory for the main site. But if a MU-era network has disabled
			 * ms-files rewriting manually, they don't need the extra directory, as they never
			 * had wp-content/uploads for the main site.)
			 */

			if ( defined( 'MULTISITE' ) ) {
				$ms_dir = '/sites/' . get_current_blog_id();
			} else {
				$ms_dir = '/' . get_current_blog_id();
			}

			$dir .= $ms_dir;
			$url .= $ms_dir;

		} elseif ( defined( 'UPLOADS' ) && ! ms_is_switched() ) {
			/*
			 * Handle the old-form ms-files.php rewriting if the network still has that enabled.
			 * When ms-files rewriting is enabled, then we only listen to UPLOADS when:
			 * 1) We are not on the main site in a post-MU network, as wp-content/uploads is used
			 *    there, and
			 * 2) We are not switched, as ms_upload_constants() hardcodes these constants to reflect
			 *    the original blog ID.
			 *
			 * Rather than UPLOADS, we actually use BLOGUPLOADDIR if it is set, as it is absolute.
			 * (And it will be set, see ms_upload_constants().) Otherwise, UPLOADS can be used, as
			 * as it is relative to ABSPATH. For the final piece: when UPLOADS is used with ms-files
			 * rewriting in multisite, the resulting URL is /files. (#WP22702 for background.)
			 */

			if ( defined( 'BLOGUPLOADDIR' ) ) {
				$dir = untrailingslashit( BLOGUPLOADDIR );
			} else {
				$dir = ABSPATH . UPLOADS;
			}
			$url = trailingslashit( $siteurl ) . 'files';
		}
	}

	$basedir = $dir;
	$baseurl = $url;

	$subdir = '';
	if ( get_option( 'uploads_use_yearmonth_folders' ) ) {
		// Generate the yearly and monthly directories.
		if ( ! $time ) {
			$time = current_time( 'mysql' );
		}
		$y      = substr( $time, 0, 4 );
		$m      = substr( $time, 5, 2 );
		$subdir = "/$y/$m";
	}

	$dir .= $subdir;
	$url .= $subdir;

	return array(
		'path'    => $dir,
		'url'     => $url,
		'subdir'  => $subdir,
		'basedir' => $basedir,
		'baseurl' => $baseurl,
		'error'   => false,
	);
}

/**
 * Gets a filename that is sanitized and unique for the given directory.
 *
 * If the filename is not unique, then a number will be added to the filename
 * before the extension, and will continue adding numbers until the filename
 * is unique.
 *
 * The callback function allows the caller to use their own method to create
 * unique file names. If defined, the callback should take three arguments:
 * - directory, base filename, and extension - and return a unique filename.
 *
 * @since 2.5.0
 *
 * @param string   $dir                      Directory.
 * @param string   $filename                 File name.
 * @param callable $unique_filename_callback Callback. Default null.
 * @return string New filename, if given wasn't unique.
 */
function wp_unique_filename( $dir, $filename, $unique_filename_callback = null ) {
	// Sanitize the file name before we begin processing.
	$filename = sanitize_file_name( $filename );

	// Initialize vars used in the wp_unique_filename filter.
	$number        = '';
	$alt_filenames = array();

	// Separate the filename into a name and extension.
	$ext  = pathinfo( $filename, PATHINFO_EXTENSION );
	$name = pathinfo( $filename, PATHINFO_BASENAME );

	if ( $ext ) {
		$ext = '.' . $ext;
	}

	// Edge case: if file is named '.ext', treat as an empty name.
	if ( $name === $ext ) {
		$name = '';
	}

	/*
	 * Increment the file number until we have a unique file to save in $dir.
	 * Use callback if supplied.
	 */
	if ( $unique_filename_callback && is_callable( $unique_filename_callback ) ) {
		$filename = call_user_func( $unique_filename_callback, $dir, $name, $ext );
	} else {
		$fname = pathinfo( $filename, PATHINFO_FILENAME );

		// Always append a number to file names that can potentially match image sub-size file names.
		if ( $fname && preg_match( '/-(?:\d+x\d+|scaled|rotated)$/', $fname ) ) {
			$number = 1;

			// At this point the file name may not be unique. This is tested below and the $number is incremented.
			$filename = str_replace( "{$fname}{$ext}", "{$fname}-{$number}{$ext}", $filename );
		}

		/*
		 * Get the mime type. Uploaded files were already checked with wp_check_filetype_and_ext()
		 * in _wp_handle_upload(). Using wp_check_filetype() would be sufficient here.
		 */
		$file_type = wp_check_filetype( $filename );
		$mime_type = $file_type['type'];

		$is_image    = ( ! empty( $mime_type ) && str_starts_with( $mime_type, 'image/' ) );
		$upload_dir  = wp_get_upload_dir();
		$lc_filename = null;

		$lc_ext = strtolower( $ext );
		$_dir   = trailingslashit( $dir );

		/*
		 * If the extension is uppercase add an alternate file name with lowercase extension.
		 * Both need to be tested for uniqueness as the extension will be changed to lowercase
		 * for better compatibility with different filesystems. Fixes an inconsistency in WP < 2.9
		 * where uppercase extensions were allowed but image sub-sizes were created with
		 * lowercase extensions.
		 */
		if ( $ext && $lc_ext !== $ext ) {
			$lc_filename = preg_replace( '|' . preg_quote( $ext ) . '$|', $lc_ext, $filename );
		}

		/*
		 * Increment the number added to the file name if there are any files in $dir
		 * whose names match one of the possible name variations.
		 */
		while ( file_exists( $_dir . $filename ) || ( $lc_filename && file_exists( $_dir . $lc_filename ) ) ) {
			$new_number = (int) $number + 1;

			if ( $lc_filename ) {
				$lc_filename = str_replace(
					array( "-{$number}{$lc_ext}", "{$number}{$lc_ext}" ),
					"-{$new_number}{$lc_ext}",
					$lc_filename
				);
			}

			if ( '' === "{$number}{$ext}" ) {
				$filename = "{$filename}-{$new_number}";
			} else {
				$filename = str_replace(
					array( "-{$number}{$ext}", "{$number}{$ext}" ),
					"-{$new_number}{$ext}",
					$filename
				);
			}

			$number = $new_number;
		}

		// Change the extension to lowercase if needed.
		if ( $lc_filename ) {
			$filename = $lc_filename;
		}

		/*
		 * Prevent collisions with existing file names that contain dimension-like strings
		 * (whether they are subsizes or originals uploaded prior to #42437).
		 */

		$files = array();
		$count = 10000;

		// The (resized) image files would have name and extension, and will be in the uploads dir.
		if ( $name && $ext && @is_dir( $dir ) && str_contains( $dir, $upload_dir['basedir'] ) ) {
			/**
			 * Filters the file list used for calculating a unique filename for a newly added file.
			 *
			 * Returning an array from the filter will effectively short-circuit retrieval
			 * from the filesystem and return the passed value instead.
			 *
			 * @since 5.5.0
			 *
			 * @param array|null $files    The list of files to use for filename comparisons.
			 *                             Default null (to retrieve the list from the filesystem).
			 * @param string     $dir      The directory for the new file.
			 * @param string     $filename The proposed filename for the new file.
			 */
			$files = apply_filters( 'pre_wp_unique_filename_file_list', null, $dir, $filename );

			if ( null === $files ) {
				// List of all files and directories contained in $dir.
				$files = @scandir( $dir );
			}

			if ( ! empty( $files ) ) {
				// Remove "dot" dirs.
				$files = array_diff( $files, array( '.', '..' ) );
			}

			if ( ! empty( $files ) ) {
				$count = count( $files );

				/*
				 * Ensure this never goes into infinite loop as it uses pathinfo() and regex in the check,
				 * but string replacement for the changes.
				 */
				$i = 0;

				while ( $i <= $count && _wp_check_existing_file_names( $filename, $files ) ) {
					$new_number = (int) $number + 1;

					// If $ext is uppercase it was replaced with the lowercase version after the previous loop.
					$filename = str_replace(
						array( "-{$number}{$lc_ext}", "{$number}{$lc_ext}" ),
						"-{$new_number}{$lc_ext}",
						$filename
					);

					$number = $new_number;
					++$i;
				}
			}
		}

		/*
		 * Check if an image will be converted after uploading or some existing image sub-size file names may conflict
		 * when regenerated. If yes, ensure the new file name will be unique and will produce unique sub-sizes.
		 */
		if ( $is_image ) {
			$output_formats = wp_get_image_editor_output_format( $_dir . $filename, $mime_type );
			$alt_types      = array();

			if ( ! empty( $output_formats[ $mime_type ] ) ) {
				// The image will be converted to this format/mime type.
				$alt_mime_type = $output_formats[ $mime_type ];

				// Other types of images whose names may conflict if their sub-sizes are regenerated.
				$alt_types   = array_keys( array_intersect( $output_formats, array( $mime_type, $alt_mime_type ) ) );
				$alt_types[] = $alt_mime_type;
			} elseif ( ! empty( $output_formats ) ) {
				$alt_types = array_keys( array_intersect( $output_formats, array( $mime_type ) ) );
			}

			// Remove duplicates and the original mime type. It will be added later if needed.
			$alt_types = array_unique( array_diff( $alt_types, array( $mime_type ) ) );

			foreach ( $alt_types as $alt_type ) {
				$alt_ext = wp_get_default_extension_for_mime_type( $alt_type );

				if ( ! $alt_ext ) {
					continue;
				}

				$alt_ext      = ".{$alt_ext}";
				$alt_filename = preg_replace( '|' . preg_quote( $lc_ext ) . '$|', $alt_ext, $filename );

				$alt_filenames[ $alt_ext ] = $alt_filename;
			}

			if ( ! empty( $alt_filenames ) ) {
				/*
				 * Add the original filename. It needs to be checked again
				 * together with the alternate filenames when $number is incremented.
				 */
				$alt_filenames[ $lc_ext ] = $filename;

				// Ensure no infinite loop.
				$i = 0;

				while ( $i <= $count && _wp_check_alternate_file_names( $alt_filenames, $_dir, $files ) ) {
					$new_number = (int) $number + 1;

					foreach ( $alt_filenames as $alt_ext => $alt_filename ) {
						$alt_filenames[ $alt_ext ] = str_replace(
							array( "-{$number}{$alt_ext}", "{$number}{$alt_ext}" ),
							"-{$new_number}{$alt_ext}",
							$alt_filename
						);
					}

					/*
					 * Also update the $number in (the output) $filename.
					 * If the extension was uppercase it was already replaced with the lowercase version.
					 */
					$filename = str_replace(
						array( "-{$number}{$lc_ext}", "{$number}{$lc_ext}" ),
						"-{$new_number}{$lc_ext}",
						$filename
					);

					$number = $new_number;
					++$i;
				}
			}
		}
	}

	/**
	 * Filters the result when generating a unique file name.
	 *
	 * @since 4.5.0
	 * @since 5.8.1 The `$alt_filenames` and `$number` parameters were added.
	 *
	 * @param string        $filename                 Unique file name.
	 * @param string        $ext                      File extension. Example: ".png".
	 * @param string        $dir                      Directory path.
	 * @param callable|null $unique_filename_callback Callback function that generates the unique file name.
	 * @param string[]      $alt_filenames            Array of alternate file names that were checked for collisions.
	 * @param int|string    $number                   The highest number that was used to make the file name unique
	 *                                                or an empty string if unused.
	 */
	return apply_filters( 'wp_unique_filename', $filename, $ext, $dir, $unique_filename_callback, $alt_filenames, $number );
}

/**
 * Helper function to test if each of an array of file names could conflict with existing files.
 *
 * @since 5.8.1
 * @access private
 *
 * @param string[] $filenames Array of file names to check.
 * @param string   $dir       The directory containing the files.
 * @param array    $files     An array of existing files in the directory. May be empty.
 * @return bool True if the tested file name could match an existing file, false otherwise.
 */
function _wp_check_alternate_file_names( $filenames, $dir, $files ) {
	foreach ( $filenames as $filename ) {
		if ( file_exists( $dir . $filename ) ) {
			return true;
		}

		if ( ! empty( $files ) && _wp_check_existing_file_names( $filename, $files ) ) {
			return true;
		}
	}

	return false;
}

/**
 * Helper function to check if a file name could match an existing image sub-size file name.
 *
 * @since 5.3.1
 * @access private
 *
 * @param string $filename The file name to check.
 * @param array  $files    An array of existing files in the directory.
 * @return bool True if the tested file name could match an existing file, false otherwise.
 */
function _wp_check_existing_file_names( $filename, $files ) {
	$fname = pathinfo( $filename, PATHINFO_FILENAME );
	$ext   = pathinfo( $filename, PATHINFO_EXTENSION );

	// Edge case, file names like `.ext`.
	if ( empty( $fname ) ) {
		return false;
	}

	if ( $ext ) {
		$ext = ".$ext";
	}

	$regex = '/^' . preg_quote( $fname ) . '-(?:\d+x\d+|scaled|rotated)' . preg_quote( $ext ) . '$/i';

	foreach ( $files as $file ) {
		if ( preg_match( $regex, $file ) ) {
			return true;
		}
	}

	return false;
}

/**
 * Creates a file in the upload folder with given content.
 *
 * If there is an error, then the key 'error' will exist with the error message.
 * If success, then the key 'file' will have the unique file path, the 'url' key
 * will have the link to the new file. and the 'error' key will be set to false.
 *
 * This function will not move an uploaded file to the upload folder. It will
 * create a new file with the content in $bits parameter. If you move the upload
 * file, read the content of the uploaded file, and then you can give the
 * filename and content to this function, which will add it to the upload
 * folder.
 *
 * The permissions will be set on the new file automatically by this function.
 *
 * @since 2.0.0
 *
 * @param string      $name       Filename.
 * @param null|string $deprecated Not used. Set to null.
 * @param string      $bits       File content
 * @param string|null $time       Optional. Time formatted in 'yyyy/mm'. Default null.
 * @return array {
 *     Information about the newly-uploaded file.
 *
 *     @type string       $file  Filename of the newly-uploaded file.
 *     @type string       $url   URL of the uploaded file.
 *     @type string       $type  File type.
 *     @type string|false $error Error message, if there has been an error.
 * }
 */
function wp_upload_bits( $name, $deprecated, $bits, $time = null ) {
	if ( ! empty( $deprecated ) ) {
		_deprecated_argument( __FUNCTION__, '2.0.0' );
	}

	if ( empty( $name ) ) {
		return array( 'error' => __( 'Empty filename' ) );
	}

	$wp_filetype = wp_check_filetype( $name );
	if ( ! $wp_filetype['ext'] && ! current_user_can( 'unfiltered_upload' ) ) {
		return array( 'error' => __( 'Sorry, you are not allowed to upload this file type.' ) );
	}

	$upload = wp_upload_dir( $time );

	if ( false !== $upload['error'] ) {
		return $upload;
	}

	/**
	 * Filters whether to treat the upload bits as an error.
	 *
	 * Returning a non-array from the filter will effectively short-circuit preparing the upload bits
	 * and return that value instead. An error message should be returned as a string.
	 *
	 * @since 3.0.0
	 *
	 * @param array|string $upload_bits_error An array of upload bits data, or error message to return.
	 */
	$upload_bits_error = apply_filters(
		'wp_upload_bits',
		array(
			'name' => $name,
			'bits' => $bits,
			'time' => $time,
		)
	);
	if ( ! is_array( $upload_bits_error ) ) {
		$upload['error'] = $upload_bits_error;
		return $upload;
	}

	$filename = wp_unique_filename( $upload['path'], $name );

	$new_file = $upload['path'] . "/$filename";
	if ( ! wp_mkdir_p( dirname( $new_file ) ) ) {
		if ( str_starts_with( $upload['basedir'], ABSPATH ) ) {
			$error_path = str_replace( ABSPATH, '', $upload['basedir'] ) . $upload['subdir'];
		} else {
			$error_path = wp_basename( $upload['basedir'] ) . $upload['subdir'];
		}

		$message = sprintf(
			/* translators: %s: Directory path. */
			__( 'Unable to create directory %s. Is its parent directory writable by the server?' ),
			$error_path
		);
		return array( 'error' => $message );
	}

	$ifp = @fopen( $new_file, 'wb' );
	if ( ! $ifp ) {
		return array(
			/* translators: %s: File name. */
			'error' => sprintf( __( 'Could not write file %s' ), $new_file ),
		);
	}

	fwrite( $ifp, $bits );
	fclose( $ifp );
	clearstatcache();

	// Set correct file permissions.
	$stat  = @ stat( dirname( $new_file ) );
	$perms = $stat['mode'] & 0007777;
	$perms = $perms & 0000666;
	chmod( $new_file, $perms );
	clearstatcache();

	// Compute the URL.
	$url = $upload['url'] . "/$filename";

	if ( is_multisite() ) {
		clean_dirsize_cache( $new_file );
	}

	/** This filter is documented in wp-admin/includes/file.php */
	return apply_filters(
		'wp_handle_upload',
		array(
			'file'  => $new_file,
			'url'   => $url,
			'type'  => $wp_filetype['type'],
			'error' => false,
		),
		'sideload'
	);
}

/**
 * Retrieves the file type based on the extension name.
 *
 * @since 2.5.0
 *
 * @param string $ext The extension to search.
 * @return string|null The file type, example: audio, video, document, spreadsheet, etc.
 */
function wp_ext2type( $ext ) {
	$ext = strtolower( $ext );

	$ext2type = wp_get_ext_types();
	foreach ( $ext2type as $type => $exts ) {
		if ( in_array( $ext, $exts, true ) ) {
			return $type;
		}
	}
	return null;
}

/**
 * Returns the first matched extension for the mime type, as mapped from wp_get_mime_types().
 *
 * @since 5.8.1
 *
 * @param string $mime_type The mime type to search.
 * @return string|false The first matching file extension, or false if no extensions are found
 *                      for the given mime type.
 */
function wp_get_default_extension_for_mime_type( $mime_type ) {
	$extensions = explode( '|', array_search( $mime_type, wp_get_mime_types(), true ) );

	if ( empty( $extensions[0] ) ) {
		return false;
	}

	return $extensions[0];
}

/**
 * Retrieves the file type from the file name.
 *
 * You can optionally define the mime array, if needed.
 *
 * @since 2.0.4
 *
 * @param string        $filename File name or path.
 * @param string[]|null $mimes    Optional. Array of allowed mime types keyed by their file extension regex.
 *                                Defaults to the result of get_allowed_mime_types().
 * @return array {
 *     Values for the extension and mime type.
 *
 *     @type string|false $ext  File extension, or false if the file doesn't match a mime type.
 *     @type string|false $type File mime type, or false if the file doesn't match a mime type.
 * }
 */
function wp_check_filetype( $filename, $mimes = null ) {
	if ( empty( $mimes ) ) {
		$mimes = get_allowed_mime_types();
	}
	$type = false;
	$ext  = false;

	foreach ( $mimes as $ext_preg => $mime_match ) {
		$ext_preg = '!\.(' . $ext_preg . ')$!i';
		if ( preg_match( $ext_preg, $filename, $ext_matches ) ) {
			$type = $mime_match;
			$ext  = $ext_matches[1];
			break;
		}
	}

	return compact( 'ext', 'type' );
}

/**
 * Attempts to determine the real file type of a file.
 *
 * If unable to, the file name extension will be used to determine type.
 *
 * If it's determined that the extension does not match the file's real type,
 * then the "proper_filename" value will be set with a proper filename and extension.
 *
 * Currently this function only supports renaming images validated via wp_get_image_mime().
 *
 * @since 3.0.0
 *
 * @param string        $file     Full path to the file.
 * @param string        $filename The name of the file (may differ from $file due to $file being
 *                                in a tmp directory).
 * @param string[]|null $mimes    Optional. Array of allowed mime types keyed by their file extension regex.
 *                                Defaults to the result of get_allowed_mime_types().
 * @return array {
 *     Values for the extension, mime type, and corrected filename.
 *
 *     @type string|false $ext             File extension, or false if the file doesn't match a mime type.
 *     @type string|false $type            File mime type, or false if the file doesn't match a mime type.
 *     @type string|false $proper_filename File name with its correct extension, or false if it cannot be determined.
 * }
 */
function wp_check_filetype_and_ext( $file, $filename, $mimes = null ) {
	$proper_filename = false;

	// Do basic extension validation and MIME mapping.
	$wp_filetype = wp_check_filetype( $filename, $mimes );
	$ext         = $wp_filetype['ext'];
	$type        = $wp_filetype['type'];

	// We can't do any further validation without a file to work with.
	if ( ! file_exists( $file ) ) {
		return compact( 'ext', 'type', 'proper_filename' );
	}

	$real_mime = false;

	// Validate image types.
	if ( $type && str_starts_with( $type, 'image/' ) ) {

		// Attempt to figure out what type of image it actually is.
		$real_mime = wp_get_image_mime( $file );

		$heic_images_extensions = array(
			'heif',
			'heics',
			'heifs',
		);

		if ( $real_mime && ( $real_mime !== $type || in_array( $ext, $heic_images_extensions, true ) ) ) {
			/**
			 * Filters the list mapping image mime types to their respective extensions.
			 *
			 * @since 3.0.0
			 *
			 * @param array $mime_to_ext Array of image mime types and their matching extensions.
			 */
			$mime_to_ext = apply_filters(
				'getimagesize_mimes_to_exts',
				array(
					'image/jpeg'          => 'jpg',
					'image/png'           => 'png',
					'image/gif'           => 'gif',
					'image/bmp'           => 'bmp',
					'image/tiff'          => 'tif',
					'image/webp'          => 'webp',
					'image/avif'          => 'avif',

					/*
					 * In theory there are/should be file extensions that correspond to the
					 * mime types: .heif, .heics and .heifs. However it seems that HEIC images
					 * with any of the mime types commonly have a .heic file extension.
					 * Seems keeping the status quo here is best for compatibility.
					 */
					'image/heic'          => 'heic',
					'image/heif'          => 'heic',
					'image/heic-sequence' => 'heic',
					'image/heif-sequence' => 'heic',
				)
			);

			// Replace whatever is after the last period in the filename with the correct extension.
			if ( ! empty( $mime_to_ext[ $real_mime ] ) ) {
				$filename_parts = explode( '.', $filename );

				array_pop( $filename_parts );
				$filename_parts[] = $mime_to_ext[ $real_mime ];
				$new_filename     = implode( '.', $filename_parts );

				if ( $new_filename !== $filename ) {
					$proper_filename = $new_filename; // Mark that it changed.
				}

				// Redefine the extension / MIME.
				$wp_filetype = wp_check_filetype( $new_filename, $mimes );
				$ext         = $wp_filetype['ext'];
				$type        = $wp_filetype['type'];
			} else {
				// Reset $real_mime and try validating again.
				$real_mime = false;
			}
		}
	}

	// Validate files that didn't get validated during previous checks.
	if ( $type && ! $real_mime && extension_loaded( 'fileinfo' ) ) {
		$finfo     = finfo_open( FILEINFO_MIME_TYPE );
		$real_mime = finfo_file( $finfo, $file );

		if ( PHP_VERSION_ID < 80100 ) { // finfo_close() has no effect as of PHP 8.1.
			finfo_close( $finfo );
		}

		$google_docs_types = array(
			'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
			'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
		);

		foreach ( $google_docs_types as $google_docs_type ) {
			/*
			 * finfo_file() can return duplicate mime type for Google docs,
			 * this conditional reduces it to a single instance.
			 *
			 * @see https://bugs.php.net/bug.php?id=77784
			 * @see https://core.trac.wordpress.org/ticket/57898
			 */
			if ( 2 === substr_count( $real_mime, $google_docs_type ) ) {
				$real_mime = $google_docs_type;
			}
		}

		// fileinfo often misidentifies obscure files as one of these types.
		$nonspecific_types = array(
			'application/octet-stream',
			'application/encrypted',
			'application/CDFV2-encrypted',
			'application/zip',
		);

		/*
		 * If $real_mime doesn't match the content type we're expecting from the file's extension,
		 * we need to do some additional vetting. Media types and those listed in $nonspecific_types are
		 * allowed some leeway, but anything else must exactly match the real content type.
		 */
		if ( in_array( $real_mime, $nonspecific_types, true ) ) {
			// File is a non-specific binary type. That's ok if it's a type that generally tends to be binary.
			if ( ! in_array( substr( $type, 0, strcspn( $type, '/' ) ), array( 'application', 'video', 'audio' ), true ) ) {
				$type = false;
				$ext  = false;
			}
		} elseif ( str_starts_with( $real_mime, 'video/' ) || str_starts_with( $real_mime, 'audio/' ) ) {
			/*
			 * For these types, only the major type must match the real value.
			 * This means that common mismatches are forgiven: application/vnd.apple.numbers is often misidentified as application/zip,
			 * and some media files are commonly named with the wrong extension (.mov instead of .mp4)
			 */
			if ( substr( $real_mime, 0, strcspn( $real_mime, '/' ) ) !== substr( $type, 0, strcspn( $type, '/' ) ) ) {
				$type = false;
				$ext  = false;
			}
		} elseif ( 'text/plain' === $real_mime ) {
			// A few common file types are occasionally detected as text/plain; allow those.
			if ( ! in_array(
				$type,
				array(
					'text/plain',
					'text/csv',
					'application/csv',
					'text/richtext',
					'text/tsv',
					'text/vtt',
				),
				true
			)
			) {
				$type = false;
				$ext  = false;
			}
		} elseif ( 'application/csv' === $real_mime ) {
			// Special casing for CSV files.
			if ( ! in_array(
				$type,
				array(
					'text/csv',
					'text/plain',
					'application/csv',
				),
				true
			)
			) {
				$type = false;
				$ext  = false;
			}
		} elseif ( 'text/rtf' === $real_mime ) {
			// Special casing for RTF files.
			if ( ! in_array(
				$type,
				array(
					'text/rtf',
					'text/plain',
					'application/rtf',
				),
				true
			)
			) {
				$type = false;
				$ext  = false;
			}
		} else {
			if ( $type !== $real_mime ) {
				/*
				 * Everything else including image/* and application/*:
				 * If the real content type doesn't match the file extension, assume it's dangerous.
				 */
				$type = false;
				$ext  = false;
			}
		}
	}

	// The mime type must be allowed.
	if ( $type ) {
		$allowed = get_allowed_mime_types();

		if ( ! in_array( $type, $allowed, true ) ) {
			$type = false;
			$ext  = false;
		}
	}

	/**
	 * Filters the "real" file type of the given file.
	 *
	 * @since 3.0.0
	 * @since 5.1.0 The `$real_mime` parameter was added.
	 *
	 * @param array         $wp_check_filetype_and_ext {
	 *     Values for the extension, mime type, and corrected filename.
	 *
	 *     @type string|false $ext             File extension, or false if the file doesn't match a mime type.
	 *     @type string|false $type            File mime type, or false if the file doesn't match a mime type.
	 *     @type string|false $proper_filename File name with its correct extension, or false if it cannot be determined.
	 * }
	 * @param string        $file                      Full path to the file.
	 * @param string        $filename                  The name of the file (may differ from $file due to
	 *                                                 $file being in a tmp directory).
	 * @param string[]|null $mimes                     Array of mime types keyed by their file extension regex, or null if
	 *                                                 none were provided.
	 * @param string|false  $real_mime                 The actual mime type or false if the type cannot be determined.
	 */
	return apply_filters( 'wp_check_filetype_and_ext', compact( 'ext', 'type', 'proper_filename' ), $file, $filename, $mimes, $real_mime );
}

/**
 * Returns the real mime type of an image file.
 *
 * This depends on exif_imagetype() or getimagesize() to determine real mime types
