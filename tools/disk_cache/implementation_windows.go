//go:build windows

package disk_cache

import (
	"io/fs"
	"syscall"
)

// Windows file info does not expose an inode. The cache writes metadata by
// creating a temporary file and renaming it over the old one, so use creation
// time as a replacement-file identity. This detects rapid consecutive writes
// even when the filesystem reports the same modification time for both.
func file_inode(fi fs.FileInfo) uint64 {
	if data, ok := fi.Sys().(*syscall.Win32FileAttributeData); ok {
		return uint64(data.CreationTime.Nanoseconds())
	}
	return 0
}
