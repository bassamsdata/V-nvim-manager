import net.http
import os
import json
import cli

// TODO: organize all these commands
const home_dire = os.home_dir()
const neovim_url = 'https://github.com/neovim/neovim/releases/download/nightly/nvim-macos.tar.gz'
const target_nightly = home_dire + '/.local/share/nv_manager/nightly/'
const stable_base_url = 'https://github.com/neovim/neovim/releases/download/v'
const target_dir_nightly = home_dire + '/.local/share/nv_manager/nightly/'
const target_dir_stable = home_dire + '/.local/share/nv_manager/stable/'
const tags_url = 'https://api.github.com/repos/neovim/neovim/tags'

struct Tag {
	name string
}

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
						install_specific_stable(version)
					}
				}
			},
			cli.Command{
				name: 'update'
				execute: fn (cmd cli.Command) ! {
					update_nightly()
				}
			},
			cli.Command{
				name: 'list_remote'
				execute: fn (cmd cli.Command) ! {
					list_remote_versions()
				}
			},
			// Add other commands here
		]
	}
	app.setup()
	app.parse(os.args)
}

fn list_remote_versions() {
	resp := http.get(tags_url) or {
		eprintln('Failed to fetch Neovim versions: ${err}')
		return
	}

	tags := json.decode([]Tag, resp.body) or {
		eprintln('Failed to decode JSON: ${err}')
		return
	}
	// print only the first 7 versions
	mut count := 0
	for tag in tags {
		if count >= 7 {
			break
		}
		println(tag.name)
		count++ // Increment the count by one every time `++`
	}
}

fn install_specific_stable(version string) {
	// TODO: insure this is the correct way of dirs
	stable_url := stable_base_url + version + '/nvim-macos.tar.gz'
	target_dir := target_dir_stable + version + '/'

	// Create the target directory if it does not exist
	params := os.MkdirParams{
		mode: 0o755 // Permissions for the directory
	}
	os.mkdir_all(target_dir, params) or {
		eprintln('Failed to create target directory: ${err}')
		return
	}

	// Download the Neovim archive
	resp := http.get(stable_url) or {
		eprintln('Failed to download Neovim: ${err}')
		return
	}

	// Save the downloaded file to the target directory
	file_path := target_dir + 'nvim-macos.tar.gz'
	os.write_file(file_path, resp.body) or {
		eprintln('Failed to save Neovim archive: ${err}')
		return
	}

	// Extract the archive
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

	// TODO: Move the symlink to a new function called use
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

	println('Neovim version ${version} installed successfully!')
}

fn update_nightly() {
	nightly_path := target_nightly + 'nvim-macos'
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
	os.mkdir_all(target_nightly, params) or {
		eprintln('Failed to create target directory: ${err}')
		return
	}

	// Download the Neovim archive
	resp := http.get(neovim_url) or {
		eprintln('Failed to download Neovim: ${err}')
		return
	}

	// Save the downloaded file to the target directory
	file_path := target_nightly + 'nvim-macos.tar.gz'
	os.write_file(file_path, resp.body) or {
		eprintln('Failed to save Neovim archive: ${err}')
		return
	}

	// Extract the archive
	extract_command := 'tar xzvf ${file_path} -C ${target_nightly}'
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

	// TODO: move symlink to a new function called use
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
	neovim_binary := target_nightly + '/nvim-macos/bin/nvim'
	// Now create the new symlink
	os.symlink(neovim_binary, symlink_path) or {
		eprintln('Failed to create symlink: ${err}')
		return
	}

	println('Neovim nightly installed successfully!')
}
