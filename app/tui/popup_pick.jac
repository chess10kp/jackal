"""Anchor module for tui/popup_pick.test.jac.

Jac test files are annexes of a base module, so this companion file must
exist for `jac test tui/popup_pick.test.jac` to import. It stays empty on
purpose: annexing tests onto a real TUI module (anything transitively
pulling the demoted ui.terminal/virtual_terminal seams) crashes the current
compiler payload — see tui/overlays.jac for the same pattern.
"""
