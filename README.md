[![Actively Maintained](https://img.shields.io/badge/Maintenance%20Level-Actively%20Maintained-green.svg)](https://gist.github.com/cheerfulstoic/d107229326a01ff0f333a1d3476e068d)

        ___             ___ __      __
       /   | __  ______/ (_) /_____/ /
      / /| |/ / / / __  / / __/ __  / 
     / ___ / /_/ / /_/ / / /_/ /_/ /  
    /_/  |_\__,_/\__,_/_/\__/\__,_/   

Best Practice Auditd Configuration

## Idea

The idea of this auditd configuration is to provide a basic configuration that

- works out-of-the-box on all major Linux distributions 
- fits most use cases
- produces a reasonable amount of log data
- covers security relevant activity
- is easy to read (different sections, many comments)

## Validation

This ruleset intentionally includes `-i` so that optional distro-specific paths
do not abort loading on systems where some binaries or directories are absent.
This keeps the default deployment simple, but it also means rule load errors are
ignored.

If you want a strict pre-deployment validation, test a temporary copy with the
`-i` line removed, for example:

```bash
grep -v '^-i$' audit.rules > /tmp/audit.rules.strict
auditctl -R /tmp/audit.rules.strict
```

## UID_MIN

Several rules in `audit.rules` use `auid>=1000 -F auid!=unset` to focus on
interactive user activity and exclude unset login sessions.

`1000` is the common `UID_MIN` on many Linux distributions, but it is not
universal. If your host uses a different `UID_MIN`, check `/etc/login.defs`
and replace `1000` in `audit.rules` before deployment:

```bash
awk '$1=="UID_MIN" { print $2 }' /etc/login.defs
```

## Sources

The configuration is based on the following sources

Gov.uk auditd rules
https://github.com/gds-operations/puppet-auditd/pull/1

CentOS 7 hardening
https://highon.coffee/blog/security-harden-centos-7/#auditd---audit-daemon

Linux audit repo 
https://github.com/linux-audit/audit-userspace/tree/master/rules

Auditd high performance linux auditing
https://linux-audit.com/tuning-auditd-high-performance-linux-auditing/

### Further rules

Not all of these rules have been included. 

For PCI DSS compliance see: 
https://github.com/linux-audit/audit-userspace/blob/master/rules/30-pci-dss-v31.rules

For NISPOM compliance see:
https://github.com/linux-audit/audit-userspace/blob/master/rules/30-nispom.rules

## Video Explanations by IppSec

IppSec captured a video that explains how to detect the exploitation of the OMIGOD vulnerability using auditd. In that video, he walks you through the audit configuration maintained in this repo and explains how to use it. I highly recommend this video to get a better understanding of what is happening in the config. 

https://www.youtube.com/watch?v=lc1i9h1GyMA

## Contribution

Please contribute your changes as pull requests
