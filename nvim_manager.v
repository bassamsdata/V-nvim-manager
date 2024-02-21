import net.http
import os
import json
import cli
import term
import time

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

struct VersionEntry {
	version      string
	installed_at string
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
			cli.Command{
				name: 'rollback'
				execute: fn (cmd cli.Command) ! {
					if cmd.args.len < 1 {
						// TODO: need to bulid something like roollback 1 ro 2 ro 3...
						eprintln('Please specify a version to rollback to.')
						return
					}
					version := cmd.args[0]
					rollback_to_version(version)
				}
			},
		]
	}
	app.setup()
	app.parse(os.args)
}

// Rollback to version --------------------------------------------------------
fn rollback_to_version(version string) {
	// Path to the JSON file containing the list of installed versions
	version_list_path := home_dire + '/.local/share/nv_manager/version_list.json'
	mut version_list := []VersionEntry{}

	// Read the version list from the JSON file
	version_list_content := os.read_file(version_list_path) or {
		eprintln('Failed to read version list: ${err}')
		return
	}
	version_list = json.decode([]VersionEntry, version_list_content) or {
		eprintln('Failed to decode version list: ${err}')
		return
	}

	// Check if the requested version is in the list
	mut target_version_entry := VersionEntry{}
	for entry in version_list {
		if entry.version == version {
			target_version_entry = entry
			break
		}
	}
	if target_version_entry.version == '' {
		eprintln('The requested version is not installed.')
		return
	}

	// Path to the current active Neovim version
	current_link := home_dire + '/.local/share/nv_manager/current'

	// Remove the current symbolic link
	os.rm(current_link) or {
		eprintln('Failed to remove current symbolic link: ${err}')
		return
	}

	// Path to the version we want to rollback to
	target_version_path := target_dir_nightly + version

	// Create a new symbolic link pointing to the target version
	os.symlink(target_version_path, current_link) or {
		eprintln('Failed to create new symbolic link: ${err}')
		return
	}

	// Update the PATH environment variable to include the new version
	// This step might require shell-specific commands and may not be portable
	// Here, we're assuming that the new version is already in the PATH

	println('Rolled back to version ${version} successfully.')
}

// FIX: this function is not working
// 1. read the version list and create one if it doesn't exist
// 2. check if the version is already in the list
// 3. if it's not in the list, add it
// 4. write the new version list to the JSON file
fn update_version_list(version string) {
	version_list_path := home_dire + '/.local/share/nv_manager/version_list.json'
	mut version_list := []VersionEntry{}

	// Read the existing version list if it exists
	if os.exists(version_list_path) {
		version_list_content := os.read_file(version_list_path) or {
			eprintln('Failed to read version list: ${err}')
			return
		}
		version_list = json.decode([]VersionEntry, version_list_content) or {
			eprintln('Failed to decode version list: ${err}')
			return
		}
	}

	// Check if the version is already in the list
	for entry in version_list {
		if entry.version == version {
			// Version is already in the list, so we don't need to add it again
			return
		}
	}

	// Add the new version to the list
	new_entry := VersionEntry{
		version: version
		installed_at: time.now().strftime('%Y-%m-%d %H:%M:%S') // current date and time
	}
	version_list << new_entry

	// Write the updated version list back to the file
	version_list_content := json.encode(version_list)
	os.write_file(version_list_path, version_list_content) or {
		eprintln('Failed to write version list: ${err}')
		return
	}
}

// TODO: send it to the helper file
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

fn list_installed_versions() {
	// Define the directories where the versions are stored
	nightly_dir := target_nightly + '/nvim-macos/bin/nvim'
	stable_dir := target_dir_stable
	symlink_path := '/usr/local/bin/nvim'

	// Initialize arrays to hold the versions
	mut nightly_versions := []string{}
	mut stable_versions := []string{}

	// Scan the nightly directory
	if os.exists(nightly_dir) {
		entries := os.ls(nightly_dir) or { [] }
		for entry in entries {
			if os.is_dir(os.join_path(nightly_dir, entry)) {
				nightly_versions << entry
			}
		}
	}

	// Scan the stable directory
	if os.exists(stable_dir) {
		entries := os.ls(stable_dir) or { [] }
		for entry in entries {
			if os.is_dir(os.join_path(stable_dir, entry)) {
				stable_versions << entry
			}
		}
	}

	// TODO: it should be a better way to style this
	// Print the header
	println('Installed Versions:')
	println('---------------------')
	// Print the versions with a marker for the current version
	current_version := get_current_version(symlink_path)
	println('Current version: ${current_version}')
	// Print the nightly versions
	for version in stable_versions {
		marker := if version == current_version { '*' } else { '' }
		println('${version}${marker}')
	}
	for version in nightly_versions {
		marker := if version == current_version { '*' } else { '' }
		println('${version}${marker}')
	}

	// Print the nightly versions
	println('Nightly versions:')
	for version in nightly_versions {
		println('- ${version}')
	}

	// Print the stable versions
	println('Stable versions:')
	for version in stable_versions {
		println('- ${version}')
	}

	// Print the footer
	println('---------------------')
}

// TODO: delete this one
fn get_current_version(symlink_path string) string {
	// Read the symlink to get the path of the active Neovim binary
	real_path := os.execute('readlink ${symlink_path}')
	// Extract the version from the path
	components := real_path.output.trim('\n')
	component1, component2 := extract_version_from_path(components)
	println('component1: ${component1}, component2: ${component2}')
	// Assume the version is the third last segment of the path
	if component1 != '' {
		return component2
	}
	return ''
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
	update_version_list('nightly')

	// Remove the downloaded archive
	os.rm(file_path) or {
		eprintln('Failed to remove the Neovim archive')
		return
	}

	println('Neovim nightly installed successfully!')
}
