"""Compatibility entry point: regenerate the current manuals from shared content."""
from pathlib import Path
import runpy
runpy.run_path(str(Path(__file__).with_name("generate-operating-manuals.py")), run_name="__main__")
