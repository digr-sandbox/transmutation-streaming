#!/usr/bin/env python3
"""
DB Schema Validator - Main Entry Point

This script serves as the entry point for the database schema validation tools.
It locates and executes the main database tools script in the Angular scripts 
directory, forwarding any command-line arguments.

The validator helps ensure that the database schema matches the expected structure
defined by TypeORM entity files, identifying missing tables, columns, or incorrect
data types.

Usage:
    python db_schema_validator.py [arguments] [--debug]

Arguments are forwarded to the underlying tools script.
"""

import os
import sys
import subprocess
import argparse
from pathlib import Path

# Add parent directory to path to import logging_utils
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
from src.logging_utils import setup_logging


def main():
    """
    Main entry point for the schema validator.
    
    Locates the DB tools script in the Angular scripts directory and executes it,
    forwarding any command-line arguments. Handles error cases such as missing
    script files or Python version compatibility.
    
    Returns:
        int: Exit code (0 for success, non-zero for failures)
    """
    # Parse debug flag but don't consume it from args
    parser = argparse.ArgumentParser(add_help=False)
    parser.add_argument('--debug', action='store_true', help='Enable debug logging')
    debug_args, remaining_args = parser.parse_known_args()
    
    # Set up logging using the new logging_utils module
    logger = setup_logging('db_schema_validator', debug_args.debug)
    
    # Remove the debug flag if we added it so it doesn't confuse the tools script
    if debug_args.debug and '--debug' in sys.argv:
        sys.argv.remove('--debug')

    # Find the actual db_tools.py script in the angular/scripts directory
    script_dir = Path(__file__).parent / "angular" / "scripts"
    tools_script = script_dir / "db_tools.py"
    
    logger.debug(f"Looking for tools script at {tools_script}")
    
    if not tools_script.exists():
        logger.error(f"Could not find the tools script at {tools_script}")
        logger.error("Make sure you have the complete set of schema validator scripts in the angular/scripts directory.")
        return 1
    
    # Check Python version
    if sys.version_info < (3, 6):
        logger.error("This script requires Python 3.6 or higher")
        logger.error(f"Current Python version: {sys.version}")
        return 1
    
    # Forward all arguments to the tools script
    cmd = [sys.executable, str(tools_script)] + remaining_args
    
    logger.debug(f"Forwarding to tools script with command: {' '.join(cmd)}")
    
    try:
        logger.info("Launching DB Schema Validator...")
        result = subprocess.run(cmd)
        exit_code = result.returncode
        
        if exit_code == 0:
            logger.info("DB Schema Validator completed successfully")
        else:
            logger.error(f"DB Schema Validator failed with exit code {exit_code}")
            
        return exit_code
    except Exception as e:
        logger.error(f"Error running schema validator: {str(e)}")
        import traceback
        logger.error(traceback.format_exc())
        return 1


if __name__ == "__main__":
    sys.exit(main()) 