import net.http
import os
import cli

const home_dire = os.home_dir()
const neovim_url = 'https://github.com/neovim/neovim/releases/download/nightly/nvim-macos.tar.gz'
const target_dir = home_dire + '/.local/share/nv_manager/nightly/'

fn main() {
	mut app := cli.Command{
		name: 'nvimv'
		description: 'Neovim version manager'
		execute: fn (cmd cli.Command) ! {
			println('Use "nvimv install nightly" to install the latest nightly build.')
			return
		}
		commands: [
			cli.Command{
				name: 'install'
				execute: fn (cmd cli.Command) ! {
					if cmd.args.len < 1 {
						eprintln('Please specify a version to install.')
						return
					}
					version := cmd.args[0]
					if version == 'nightly' {
						install_nightly()
					} else {
						// TODO: Implement logic for installing other versions
						eprintln('Only "nightly" version is supported right now.')
					}
				}
			},
			cli.Command{
				name: 'update'
				execute: fn (cmd cli.Command) ! {
					update_nightly()
				}
			},
			// Add other commands here
		]
	}
	app.setup()
	app.parse(os.args)
}

fn update_nightly() {
	nightly_path := target_dir + 'nvim-macos'
	if os.exists(nightly_path) {
		// Remove the existing nightly version
		os.rmdir_all(nightly_path) or {
			eprintln('Failed to remove existing nightly version: ${err}')
			return
		}
	}
	// Install the new nightly version
	install_nightly()
	println('and version updated.')
}

fn install_nightly() {
	// Create the target directory if it does not exist
	params := os.MkdirParams{
		mode: 0o755 // Permissions for the directory
	}
	os.mkdir_all(target_dir, params) or {
		eprintln('Failed to create target directory: ${err}')
		return
	}

	// Download the Neovim archive
	resp := http.get(neovim_url) or {
		eprintln('Failed to download Neovim: ${err}')
		return
	}

	// Save the downloaded file to the target directory
	file_path := target_dir + 'nvim-macos.tar.gz'
	os.write_file(file_path, resp.body) or {
		eprintln('Failed to save Neovim archive: ${err}')
		return
	}

	// Extract the archive (you may need to install `tar` if it's not available)
	extract_command := 'tar xzvf ${file_path} -C ${target_dir}'
	result := os.execute(extract_command)
	if result.exit_code != 0 {
		eprintln('Failed to extract Neovim: ${result.output}')
		return
	}

	// Remove the downloaded archive
	os.rm(file_path) or {
		eprintln('Failed to remove the Neovim archive')
		return
	}

	symlink_path := '/usr/local/bin/nvim'
	// Check if the symlink already exists
	if os.exists(symlink_path) {
		// Remove the existing symlink
		os.rm(symlink_path) or {
			eprintln('Failed to remove existing symlink: ${err}')
			return
		}
	}

	// Create a symlink to the extracted binary in /usr/local/bin/
	neovim_binary := target_dir + '/nvim-macos/bin/nvim'
	// Now create the new symlink
	os.symlink(neovim_binary, symlink_path) or {
		eprintln('Failed to create symlink: ${err}')
		return
	}

	println('Neovim nightly installed successfully!')
}
