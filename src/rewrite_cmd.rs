use crate::discover::registry;

/// Run the `ask rewrite` command.
///
/// Prints the ASK-rewritten command to stdout and exits 0.
/// Exits 1 (without output) if the command has no ASK equivalent.
///
/// Used by shell hooks to rewrite commands transparently:
/// ```bash
/// REWRITTEN=$(ask rewrite "$CMD") || exit 0
/// [ "$CMD" = "$REWRITTEN" ] && exit 0  # already ASK-rewritten, skip
/// ```
pub fn run(cmd: &str) -> anyhow::Result<()> {
    let excluded = crate::config::Config::load()
        .map(|c| c.hooks.exclude_commands)
        .unwrap_or_default();

    match registry::rewrite_command(cmd, &excluded) {
        Some(rewritten) => {
            print!("{}", rewritten);
            Ok(())
        }
        None => {
            std::process::exit(1);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_run_supported_command_succeeds() {
        assert!(registry::rewrite_command("git status", &[]).is_some());
    }

    #[test]
    fn test_run_unsupported_returns_none() {
        assert!(registry::rewrite_command("htop", &[]).is_none());
    }

    #[test]
    fn test_run_already_rtk_returns_some() {
        assert_eq!(
            registry::rewrite_command("ask git status", &[]),
            Some("ask git status".into())
        );
    }
}
