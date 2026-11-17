"""Check dependencies, allowing only two known Ubuntu version metadata errors.

The installer pins pip 24.3.1, whose dependency checker is reused here.
ROS needs system site-packages, so Ubuntu's Debian version strings remain
visible. No system package metadata is edited or replaced.
"""
from pip._internal.metadata import get_default_environment
from pip._internal.operations.check import PackageDetails, check_package_set, check_unsupported
from pip._internal.utils.compatibility_tags import get_supported

environment = get_default_environment()
packages = {}
allowed = {
    "distro-info": "Invalid version: '0.23ubuntu1'",
    "python-debian": "Invalid version: '0.1.36ubuntu1'",
}
for distribution in environment.iter_installed_distributions(local_only=False, skip=()):
    name = distribution.canonical_name
    try:
        packages[name] = PackageDetails(distribution.version, list(distribution.iter_dependencies()))
    except ValueError as error:
        if str(error) != allowed.get(name) or str(distribution.location) != "/usr/lib/python3/dist-packages":
            raise
        print("Ubuntu metadata exception:", name, str(error))
missing, conflicting = check_package_set(packages)
unsupported = list(check_unsupported(environment.iter_installed_distributions(), get_supported()))
if missing or conflicting or unsupported:
    raise SystemExit("Dependency check failed: " + repr((missing, conflicting, [d.raw_name for d in unsupported])))
print("All other package metadata and dependencies passed validation.")
