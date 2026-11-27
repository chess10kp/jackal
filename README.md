# Jackal

**A fast native coding agent with a pi-compatible JavaScript extension layer.**

### Acknowledgements

- [Pi](https://pi.dev): For inspiring the TUI implementation

## Development VM

Use the shared `jackal-extra-1` Instabox VM for builds and development work. The CLI's saved login can change independently; when needed, set the `INSTABOX_API_KEY` environment variable to the Jackal-specific key stored in your private credential store. Do not put the key in this README, another tracked file, or shell history.

```sh
instabox ssh jackal-extra-1
instabox exec jackal-extra-1 --cwd /data/home/repos/jackal -- <command>
```

To verify which account or key the CLI is using, run `instabox whoami`.
