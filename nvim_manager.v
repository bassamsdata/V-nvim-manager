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
const tags_nightly_url = 'https://api.github.com/repos/neovim/neovim/releases/tags/nightly'

struct Tag {
	name string
}

struct VersionInfo {
mut:
	node_id       string
	created_at    string
	directory     string
	unique_number int
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
				description: 'install the latest nightly or a specific version'
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
				description: 'update the local nightly version'
				execute: fn (cmd cli.Command) ! {
					update_nightly()
				}
			},
			cli.Command{
				name: 'list_remote'
				description: 'list the last 7 stable remote versions'
				execute: fn (cmd cli.Command) ! {
					list_remote_versions()
				}
			},
			cli.Command{
				name: 'use'
				description: 'use a specific version e.g. `nvimv use 0.9.5` or `nvimv use nightly`'
				execute: fn (cmd cli.Command) ! {
					if cmd.args.len < 1 {
						eprintln('Please specify a version to use.')
						return
					}
					version := cmd.args[0]
					use_version(version)
				}
			},
			cli.Command{
				name: 'ls'
				description: 'list versions locally `nvimv ls local` or remotely `nvimv ls remote`'
				execute: fn (cmd cli.Command) ! {
					if cmd.args.len == 0 {
						eg := term.bright_green(' e.g. nvimv ls local')
						println('please choose either local or remote.${eg}')
						return
					}
					for arg in cmd.args {
						if arg == 'local' {
							// FIX: this is the wrong one, need to check
							print_current_version()
						} else if arg == 'remote' {
							list_installed_versions()
						} else {
							println('Unknown argument: ${arg}')
						}
					}
				}
			},
			cli.Command{
				name: 'setup'
				description: 'Setup the neovim manager directories'
				execute: fn (cmd cli.Command) ! {
					setup()
				}
			},
			cli.Command{
				name: 'rollback'
				description: 'Rollback to a specific version - only works on nightly versions e.g. `nvimv rollback 1` to rollback to most previous one'
				execute: fn (cmd cli.Command) ! {
					if cmd.args.len < 1 {
						eprintln('Please specify a version to rollback to.')
						return
					}
					version := cmd.args[0].int()
					rollback_to_version(version)
				}
			},
			cli.Command{
				name: 'check'
				description: "Check the current version that's being used"
				execute: fn (cmd cli.Command) ! {
					print_current_version()
				}
			},
			cli.Command{
				name: 'help'
				description: 'Show available commands and their descriptions'
				execute: fn (cmd cli.Command) ! {
					for command in cmd.parent.commands {
						cyan_command := term.bold(term.cyan(command.name))
						println('${cyan_command}:')
						println('\t${command.description}')
						println('')
					}
				}
			},
		]
	}
	app.setup()
	app.parse(os.args)
}

fn setup() {
	version_file_path := target_nightly + 'versions_info.json'
	if os.exists(version_file_path) {
		println('The versions_info.json file already exists.')
		return
	}

	// Define the initial content for the versions_info.json file
	initial_content := '[]' // Start with an empty JSON array

	// Write the initial content to the file
	os.write_file(version_file_path, initial_content) or {
		eprintln('Failed to create versions_info.json file: ${err}')
		return
	}

	println('The versions_info.json file has been created successfully.')
}

// Rollback to version --------------------------------------------------------
// TEST: I still need to test this - this is the first time I'm using this method
fn rollback_to_version(unique_number int) {
	// Read the list of installed versions
	version_file_path := target_nightly + 'versions_info.json'
	version_file_content := os.read_file(version_file_path) or {
		eprintln('Failed to read version file: ${err}')
		return
	}
	installed_versions := json.decode([]VersionInfo, version_file_content) or {
		eprintln('Failed to parse version file JSON: ${err}')
		return
	}

	// Find the version with the specified unique number
	mut version_to_rollback := VersionInfo{}
	for version in installed_versions {
		if version.unique_number == unique_number {
			version_to_rollback = version
			break
		}
	}

	// If no version was found, print an error and return
	if version_to_rollback.unique_number == 0 {
		eprintln('Version with unique number ${unique_number} not found.')
		return
	}

	// Activate the specified version
	symlink_path := '/usr/local/bin/nvim' // TODO: ensure the path is correct
	// FIX: modify this to use the correct path of created_date
	// created_at := version_to_rollback.created_at.custom_format('%Y-%m-%d')
	version_executable := target_nightly + version_to_rollback.node_id + '/nvim'
	os.symlink(version_executable, symlink_path) or {
		eprintln('Failed to update symlink: ${err}')
		return
	}

	println('Rolled back to Neovim version ${version_to_rollback.unique_number}')
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

// FIX: this is not working when using nightly- need refactor
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

// BUG: doesn't work if it is nightly
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

// Del: this is not a good implementation
fn extract_version_from_path(path string) (string, string) {
	components := path.split('/')
	if components.len > 6 {
		return components[6], components[7]
	}
	return '', ''
}

// TODO: need enhancements to let the user specify the version
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

// NOTE: this is almost a prod-ready function
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

// FIX: this is a pain with tghe rollback feature - needs refactor
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
	// Fetch the latest nightly release information from GitHub API
	resp := http.get(tags_nightly_url) or {
		eprintln('Failed to fetch latest nightly release information: ${err}')
		return
	}
	// FIX: change this to use object instead of array like update nightly
	mut release_info := []VersionInfo{}

	// Decode the JSON response into a struct
	release_info = json.decode([]VersionInfo, resp.body) or {
		eprintln('Failed to parse release information JSON, error: ${err}')
		return
	}

	// Extract the unique identifier and timestamp
	node_id := release_info[0].node_id
	created_at := release_info[0].created_at

	// Create the target directory if it does not exist
	params := os.MkdirParams{
		mode: 0o755 // Permissions for the directory
	}

	// Create a unique directory for the new version
	date_time_dir := time.parse_rfc3339(created_at) or {
		eprintln('Error parsing date string: ${err.msg()}')
		return
	}
	formatted_date := date_time_dir.custom_format('YYYY-MM-DD')
	version_dir := target_nightly + formatted_date + '/'
	os.mkdir_all(version_dir, params) or {
		eprintln('Failed to create version directory: ${err}')
		return
	}

	// Download the Neovim archive
	fileresp := http.get(neovim_url) or {
		eprintln('Failed to download Neovim: ${err}')
		return
	}

	// Save the downloaded file to the version directory
	file_path := version_dir + 'nvim-macos.tar.gz'
	os.write_file(file_path, fileresp.body) or {
		eprintln('Failed to save Neovim archive: ${err}')
		return
	}

	// Extract the archive
	extract_command := 'tar xzvf ${file_path} -C ${version_dir}'
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

	// After extracting the new version, read the existing versions_info.json
	version_file_path := target_nightly + 'versions_info.json'
	mut existing_versions := json.decode([]VersionInfo, os.read_file(version_file_path) or {
		eprintln('Failed to read version file: ${err}')
		return
	}) or {
		eprintln('Failed to parse version file JSON: ${err}')
		return
	}

	// Create a new VersionInfo for the current nightly version
	new_version := VersionInfo{
		node_id: node_id
		created_at: created_at
		directory: version_dir
		unique_number: existing_versions.len + 1 // Assign a unique number based on the current count
	}
	// Append the new version to the list
	existing_versions << new_version

	// Write the updated list back to the file
	version_info_json := json.encode(existing_versions)
	os.write_file(version_file_path, version_info_json) or {
		eprintln('Failed to update version file: ${err}')
		return
	}
	use_version('nightly')

	println('Neovim nightly installed successfully!')
}
