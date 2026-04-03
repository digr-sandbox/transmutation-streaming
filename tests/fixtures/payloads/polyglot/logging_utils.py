#!/usr/bin/env python3
"""
Logging Utilities Module

This module provides centralized logging setup for all scripts in the project.
It handles configuration of file-based logging with timestamp-based filenames,
console output, and debug mode control through a configuration file.

The module ensures consistent logging behavior across all scripts with the
ability to toggle debug mode through a single configuration file.
"""

import os
import sys
import json
import logging
import configparser
from datetime import datetime
from pathlib import Path


def get_debug_mode_from_config():
    """
    Get debug mode setting from the configuration file.
    
    Looks for a config.json file in the project root and retrieves
    the debug_mode setting. Creates a default config if none exists.
    
    Returns:
        bool: True if debug mode is enabled, False otherwise
    """
    config_path = Path(__file__).parent.parent / "config.json"
    
    # Default configuration
    default_config = {
        "debug_mode": False,
        "log_directory": "logs"
    }
    
    # Create config directory if it doesn't exist
    config_dir = config_path.parent
    if not config_dir.exists():
        config_dir.mkdir(parents=True, exist_ok=True)
    
    # Create config file with default settings if it doesn't exist
    if not config_path.exists():
        with open(config_path, 'w') as f:
            json.dump(default_config, f, indent=2)
        return default_config["debug_mode"]
    
    # Read config if it exists
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        debug_mode = config.get("debug_mode", False)
        print(f"Debug mode from config: {debug_mode}")
        return debug_mode
    except (json.JSONDecodeError, IOError) as e:
        print(f"Error reading config file: {e}")
        return False


def get_log_directory_from_config():
    """
    Get log directory from the configuration file.
    
    Looks for a config.json file in the project root and retrieves
    the log_directory setting.
    
    Returns:
        Path: Path to the log directory
    """
    config_path = Path(__file__).parent.parent / "config.json"
    
    try:
        with open(config_path, 'r') as f:
            config = json.load(f)
        log_dir = config.get("log_directory", "logs")
        return Path(log_dir)
    except (json.JSONDecodeError, IOError, FileNotFoundError):
        return Path("logs")


def setup_logging(script_name, cmd_debug=None):
    """
    Configure logging for a script.
    
    Sets up file-based logging with a timestamp-based filename in the configured
    log directory and adds console output. Debug mode can be controlled through 
    the config file or command-line arguments (with command-line taking precedence).
    
    Args:
        script_name (str): Name of the script (used for the log filename prefix)
        cmd_debug (bool, optional): Debug mode from command-line arguments
        
    Returns:
        logging.Logger: Configured root logger
    """
    # Determine debug mode (command-line overrides config file)
    config_debug = get_debug_mode_from_config()
    debug_mode = True if cmd_debug else config_debug
    print(f"cmd_debug: {cmd_debug}, config_debug: {config_debug}, final debug_mode: {debug_mode}")
    
    # Make sure we reset any existing logging configuration
    for handler in logging.root.handlers[:]:
        logging.root.removeHandler(handler)
    
    # Set log level based on debug mode
    log_level = logging.DEBUG if debug_mode else logging.INFO
    print(f"Setting log level to: {log_level} ({logging.getLevelName(log_level)})")
    
    # Create timestamp for log filename
    timestamp = datetime.now().strftime('%Y%m%d_%H%M%S')
    log_filename = f'{script_name}_{timestamp}.log'
    
    # Get log directory from config and create if it doesn't exist
    log_dir = get_log_directory_from_config()
    log_dir.mkdir(parents=True, exist_ok=True)
    
    # Full path to log file
    log_file_path = log_dir / log_filename
    
    # Configure logging
    logging.basicConfig(
        filename=str(log_file_path),
        level=log_level,
        format='%(asctime)s - %(levelname)s - %(message)s'
    )
    
    # Add console handler
    console = logging.StreamHandler()
    console.setLevel(logging.INFO)
    formatter = logging.Formatter('%(levelname)s - %(message)s')
    console.setFormatter(formatter)
    logging.getLogger('').addHandler(console)
    
    logger = logging.getLogger('')
    logger.info(f"Logging initialized for {script_name} with debug mode: {debug_mode}")
    logger.info(f"Log file: {log_file_path}")
    
    # Test debug logging
    logger.debug("This is a debug message - if you see this, debug logging is working")
    
    return logger 