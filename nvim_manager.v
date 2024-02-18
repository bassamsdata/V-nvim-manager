import net.http
import os
import json
import cli
import term

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
			cli.Command{
				name: 'use'
				execute: fn (cmd cli.Command) ! {
					if cmd.args.len < 1 {
						eprintln('Please specify a version to use.')
						return
					}
					version := cmd.args[0]
					use_version(version)
				}
			},
			// TODO: combine both command in one
			cli.Command{
				name: 'check'
				execute: fn (cmd cli.Command) ! {
					print_current_version()
				}
			},
			cli.Command{
				name: 'list_installed'
				execute: fn (cmd cli.Command) ! {
					list_installed_versions()
				}
			},
			// Add other commands here
		]
	}
	app.setup()
	app.parse(os.args)
}

// TODO: move a lot of these helper functions to different file
// Function to print a header with a divider line
fn print_header(text string, divider string) {
	header := term.header(text, divider)
	println(header)
}

// Function to print a message with a specific color
fn print_colored_message(color_function fn (string) string, message string) {
	colored_message := color_function(message)
	println(colored_message)
}

// Function to print a warning message in yellow
fn print_warning_message(message string) {
	print_colored_message(term.warn_message, message)
}

// Function to print an error message in red
fn print_error_message(message string) {
	print_colored_message(term.fail_message, message)
}

// Function to print a success message in green
fn print_success_message(message string) {
	print_colored_message(term.ok_message, message)
}

// Function to print a list of items with a specific prefix
fn print_item_list(prefix string, items []string) {
	for item in items {
		println('${prefix} ${item}')
	}
}
fn use_version(version string) {
	symlink_path := '/usr/local/bin/nvim'
	mut neovim_binary := ''

	// Determine the binary path based on the version
	if version == 'nightly' {
		neovim_binary = target_nightly + '/nvim-macos/bin/nvim'
	} else {
		neovim_binary = target_dir_stable + version + '/nvim-macos/bin/nvim'
	}

	// Check if the specified version's binary exists
	if !os.exists(neovim_binary) {
		eprintln('The specified version (${version}) is not installed.')
		eprintln('Please install the version using "nvimv install ${version}".')
		return
	}

	// Remove the existing symlink
	if os.exists(symlink_path) {
		os.rm(symlink_path) or {
			eprintln('Failed to remove existing symlink: ${err}')
			return
		}
	}

	// Create a new symlink to the specified version's binary
	os.symlink(neovim_binary, symlink_path) or {
		eprintln('Failed to create symlink: ${err}')
		return
	}

	println('Using Neovim version ${version} now.')
}

fn print_current_version() {
	version := check_current_version()
	println('Currently using Neovim version: ${version} ')
}

fn check_current_version() string {
	symlink_path := '/usr/local/bin/nvim'
	if !os.exists(symlink_path) || !os.is_link(symlink_path) {
		eprintln('Neovim is not symlinked.')
		return ''
	}

	// Use the `readlink` command to get the absolute path of the symlink
	result := os.execute('readlink ${symlink_path}')
	if result.exit_code != 0 {
		eprintln('Failed to execute readlink command: ${result.output}')
		return ''
	}

	// Parse the output to find the version
	// This assumes the symlink output includes the version in the path
	symlink_target := result.output.trim('\n') // Correct usage of trim_space
	major_version, minor_version := extract_version_from_path(symlink_target)
	if major_version == '' {
		eprintln('Failed to parse version from symlink target.')
		return ''
	}
	return minor_version
}

fn extract_version_from_path(path string) (string, string) {
	components := path.split('/')
	if components.len > 6 {
		return components[6], components[7]
	}
	return '', ''
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

	use_version(version)

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

  // TODO: add rollback feature and remove this to if or different command
	// Remove the downloaded archive
	os.rm(file_path) or {
		eprintln('Failed to remove the Neovim archive')
		return
	}

	use_version('nightly')

	println('Neovim nightly installed successfully!')
}
