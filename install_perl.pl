#!/usr/bin/env perl

use strict;
use warnings;
use warnings qw( FATAL utf8 );
use utf8;
use open qw( :encoding(UTF-8) :std );
use charnames qw( :full :short );
use Carp;
use English qw(-no_match_vars);
$Params::Check::PRESERVE_CASE = 1;    #Do not convert to lower case

use Getopt::Long;
use Cwd;
use Cwd qw(abs_path);
use FindBin qw($Bin);                 #Find directory of script
use IO::Handle;
use File::Basename qw(dirname basename fileparse);
use File::Spec::Functions qw(catfile catdir devnull);
use Readonly;

## MIPs lib/
use lib catdir( $Bin, 'lib' );        #Add MIPs internal lib
use MIP::Language::Shell qw(create_bash_file);
use Program::Download::Wget qw(wget);
use MIP::Gnu::Bash qw(gnu_cd);
use MIP::Gnu::Coreutils qw(gnu_cp gnu_rm gnu_mv gnu_mkdir gnu_ln gnu_chmod );
use MIP::PacketManager::Conda
  qw{ conda_source_activate conda_source_deactivate };
use Script::Utils qw(help set_default_array_parameters);
use MIP::Check::Path qw{ check_dir_path_exist };
use MIP::Recipes::Install::Conda
  qw{ setup_conda_env install_bioconda_packages finish_bioconda_package_install };

our $USAGE = build_usage( {} );

## Constants
Readonly my $SPACE   => q{ };
Readonly my $NEWLINE => qq{\n};

### Set parameter default

my %default_parameter;

## Perl Modules
$parameter{perl_version} = '5.18.2';


# GRCh38.86 but check current on the snpEff sourceForge
$array_parameter{snpeff_genome_versions}{default} =
  [qw(GRCh37.75 GRCh38.86)];
$array_parameter{reference_genome_versions}{default} = [qw(GRCh37 hg38)];
$array_parameter{perl_modules}{default}              = [
    'Modern::Perl',              # MIP
    'IPC::System::Simple',       # MIP
    'Path::Iterator::Rule',      # MIP
    'YAML',                      # MIP
    'Log::Log4perl',             # MIP
    'List::Util',                # MIP
    'List::MoreUtils',           # MIP
    'Readonly',                  # MIP
    'Scalar::Util::Numeric',     # MIP
    'Set::IntervalTree',         # MIP/vcfParser.pl
    'Net::SSLeay',               # VEP
    'LWP::Simple',               # VEP
    'LWP::Protocol::https',      # VEP
    'PerlIO::gzip',              # VEP
    'IO::Uncompress::Gunzip',    # VEP
    'HTML::Lint',                # VEP
    'Archive::Zip',              # VEP
    'Archive::Extract',          # VEP
    'DBI',                       # VEP
    'JSON',                      # VEP
    'DBD::mysql',                # VEP
    'CGI',                       # VEP
    'Sereal::Encoder',           # VEP
    'Sereal::Decoder',           # VEP
    'Bio::Root::Version',        # VEP
    'Module::Build',             # VEP
    'File::Copy::Recursive',     # VEP
];

my $VERSION = '1.0.0';

###User Options
GetOptions(
    'pev|perl_version=s'            => \$parameter{perl_version},
    'pei|perl_install'              => \$parameter{perl_install},
    'pevs|perl_skip_test'           => \$parameter{perl_skip_test},
    'pm|perl_modules:s'             => \@{ $parameter{perl_modules} },
    'pmf|perl_modules_force'        => \$parameter{perl_modules_force},
    'ppd|print_parameters_default'  => sub {
        print_parameters(
            {
                parameter_href       => \%parameter,
                array_parameter_href => \%array_parameter,
            }
        );
        exit;
    },    # Display parameter defaults
    'q|quiet' => \$parameter{quiet},
    'h|help'  => sub {
        print STDOUT $USAGE, "\n";
        exit;
    },    #Display help text
    'ver|version' => sub {
        print STDOUT "\n" . basename($PROGRAM_NAME) . q{ } . $VERSION, "\n\n";
        exit;
    },    #Display version number
    'v|verbose' => \$parameter{verbose},
)
  #or croak Script::Utils::help(
  #  {
  #      USAGE     => $USAGE,
  #      exit_code => 1,
  #  }
  #);

## Set default for array parameters
Script::Utils::set_default_array_parameters(
    {
        parameter_href       => \%parameter,
        array_parameter_href => \%array_parameter,
    }
);

##########
###MAIN###
##########

# Create anonymous filehandle
my $FILEHANDLE = IO::Handle->new();

# Installation instruction file
my $file_name_path = catfile( cwd(), 'mip.sh' );

open $FILEHANDLE, '>', $file_name_path
  or
  croak( q{Cannot write to '} . $file_name_path . q{' :} . $OS_ERROR . "\n" );


  #if ( @{ $parameter{select_programs} } ) {
  #
  #    if ( ( grep { $_ eq 'perl' } @{ $parameter{select_programs} } ) )
  #    {    #If element is part of array
  #
  #        perl(
  #            {
  #                parameter_href => \%parameter,
  #                FILEHANDLE     => $FILEHANDLE,
  #            }
  #        );
  #    }
  #}
  #else {
  #
  #    perl(
  #        {
  #            parameter_href => \%parameter,
  #            FILEHANDLE     => $FILEHANDLE,
  #        }
  #    );
  #}


close($FILEHANDLE);


#################
###SubRoutines###
#################

#sub build_usage {
#
###build_usage
#
###Function : Build the USAGE instructions
###Returns  : ""
###Arguments: $script_name
###         : $script_name => Name of the script
#
#    my ($arg_href) = @_;
#
#    ## Default(s)
#    my $script_name;
#
#    my $tmpl = {
#        script_name => {
#            default     => basename($0),
#            strict_type => 1,
#            store       => \$script_name,
#        },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    return <<"END_USAGE";
# $script_name [options]
#    -env/--conda_environment conda environment (Default: "")
#    -cdp/--conda_dir_path The conda directory path (Default: "HOME/miniconda")
#    -cdu/--conda_update Update conda before installing (Supply flag to enable)
#    -bvc/--bioconda Set the module version of the programs that can be installed with bioconda (e.g. 'bwa=0.7.12')
#    -pip/--pip Set the module version of the programs that can be installed with pip (e.g. 'genmod=3.7.2')
#    -pyv/--python_version Set the env python version (Default: "2.7")
#
#    ## SHELL
#    -pei/--perl_install Install perl (Supply flag to enable)
#    -pev/--perl_version Set the perl version (defaults: "5.18.2")
#    -pevs/--perl_skip_test Skip "tests" in perl installation
#    -pm/--perl_modules Set the perl modules to be installed via cpanm (Default: ["Modern::Perl", "List::Util", "IPC::System::Simple", "Path::Iterator::Rule", "YAML", "Log::Log4perl", "Set::IntervalTree", "Net::SSLeay",P, "LWP::Simple", "LWP::Protocol::https", "Archive::Zip", "Archive::Extract", "DBI","JSON", "DBD::mysql", "CGI", "Sereal::Encoder", "Sereal::Decoder", "Bio::Root::Version", "Module::Build"])
#    -pmf/--perl_modules_force Force installation of perl modules
#    -pic/--picardtools Set the picardtools version (Default: "2.5.9"),
#    -sbb/--sambamba Set the sambamba version (Default: "0.6.6")
#    -bet/--bedtools Set the bedtools version (Default: "2.26.0")
#    -vt/--vt Set the vt version (Default: "0.57")
#    -plk/--plink  Set the plink version (Default: "160224")
#    -snpg/--snpeff_genome_versions Set the snpEff genome version (Default: ["GRCh37.75", "GRCh38.82"])
#    -vep/--varianteffectpredictor Set the VEP version (Default: "88")
#    -vepa/--vep_auto_flag Set the VEP auto installer flags
#    -vepc/--vep_cache_dir Specify the cache directory to use (whole path; defaults to "[--conda_dir_path]/ensembl-tools-release-varianteffectpredictorVersion/cache")
#    -vepa/--vep_assemblies Select the assembly version (Default: ["GRCh37", "GRCh38"])
#    -vepp/--vep_plugins Supply VEP plugins (Default: "UpDownDistance, LoFtool, Lof")
#    -rhc/--rhocall Set the rhocall version (Default: "0.4")
#    -rhcp/--rhocall_path Set the path to where to install rhocall (Defaults: "HOME/rhocall")
#    -cnvn/--cnvnator Set the cnvnator version (Default: 0.3.3)
#    -cnvnr/--cnvnator_root_binary Set the cnvnator root binary (Default: "root_v6.06.00.Linux-slc6-x86_64-gcc4.8.tar.gz")
#    -tid/--tiddit Set the tiddit version (Default: "1.1.6")
#    -svdb/--svdb Set the svdb version (Default: "1.0.6")
#
#    ## Utility
#    -psh/--prefer_shell Shell will be used for overlapping shell and biconda installations (Supply flag to enable)
#    -ppd/--print_parameters_default Print the parameter defaults
#    -nup/--noupdate Do not update already installed programs (Supply flag to enable)
#    -sp/--select_programs Install supplied programs e.g. -sp perl -sp bedtools (Default: "")
#    -rd/--reference_dir Reference(s) directory (Default: "")
#    -rd/--reference_genome_versions Reference versions to download ((Default: ["GRCh37", "hg38"]))
#    -q/--quiet Quiet (Supply flag to enable; no output from individual program that has a quiet flag)
#    -h/--help Display this help message
#    -ver/--version Display version
#    -v/--verbose Set verbosity
#END_USAGE
#}
#
#sub print_parameters {
#
###print_parameters
#
###Function : Print all parameters and the default values
###Returns  : ""
###Arguments: $parameter_href, $array_parameter_href
###         : $parameter_href => Holds all parameters {REF}
###         : $array_parameter_href => Hold the array parameter defaults as {REF}
#
#    my ($arg_href) = @_;
#
#    ## Flatten argument(s)
#    my $parameter_href;
#    my $array_parameter_href;
#
#    my $tmpl = {
#        parameter_href => {
#            required    => 1,
#            defined     => 1,
#            default     => {},
#            strict_type => 1,
#            store       => \$parameter_href
#        },
#        array_parameter_href => {
#            required    => 1,
#            defined     => 1,
#            default     => {},
#            strict_type => 1,
#            store       => \$array_parameter_href
#        },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    ## Set default for array parameters
#    Script::Utils::set_default_array_parameters(
#        {
#            parameter_href       => $parameter_href,
#            array_parameter_href => \%array_parameter,
#        }
#    );
#
#    foreach my $key ( keys %{$parameter_href} ) {
#
#        if ( ref( $parameter_href->{$key} ) !~ /ARRAY|HASH/ ) {
#
#            print STDOUT $key . q{ };
#            if ( $parameter_href->{$key} ) {
#
#                print $parameter_href->{$key}, "\n";
#            }
#            else {    ##Boolean value
#
#                print '0', "\n";
#            }
#        }
#        elsif ( ref( $parameter_href->{$key} ) =~ /HASH/ ) {
#
#            foreach my $program ( keys %{ $parameter_href->{$key} } ) {
#
#                print STDOUT $key . q{ } . $program . q{: }
#                  . $parameter_href->{$key}{$program}, "\n";
#            }
#        }
#        elsif ( ref( $parameter_href->{$key} ) =~ /ARRAY/ ) {
#
#            print STDOUT $key . q{: }
#              . join( " ", @{ $parameter_href->{$key} } ), "\n";
#        }
#    }
#    return;
#}
#
#sub perl {
#
###perl
#
###Function : Installs perl
###Returns  : ""
###Arguments: $parameter_href, $FILEHANDLE
###         : $parameter_href => Holds all parameters
###         : $FILEHANDLE     => Filehandle to write to
#
#    my ($arg_href) = @_;
#
#    ## Flatten argument(s)
#    my $parameter_href;
#    my $FILEHANDLE;
#
#    my $tmpl = {
#        parameter_href => {
#            required    => 1,
#            defined     => 1,
#            default     => {},
#            strict_type => 1,
#            store       => \$parameter_href
#        },
#        FILEHANDLE => { required => 1, defined => 1, store => \$FILEHANDLE },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    my $pwd = cwd();
#
#    if ( $ENV{PATH} =~ /perl-$parameter_href->{perl_version}/ ) {
#
#        if ( $parameter_href->{noupdate} ) {
#
#            print STDERR 'Found perl-'
#              . $parameter_href->{perl_version}
#              . ' in your path', "\n";
#            print STDERR 'Skipping writting installation for perl-'
#              . $parameter_href->{perl_version}, "\n";
#        }
#        else {
#
#            if ( $parameter_href->{perl_install} ) {
#
#                ## Removing specific Perl version
#                print $FILEHANDLE '### Removing specific perl version', "\n";
#                gnu_rm(
#                    {
#                        infile_path => '$HOME/perl-'
#                          . $parameter_href->{perl_version},
#                        force      => 1,
#                        recursive  => 1,
#                        FILEHANDLE => $FILEHANDLE,
#                    }
#                );
#                print $FILEHANDLE "\n\n";
#
#                install_perl_cpnam(
#                    {
#                        parameter_href => $parameter_href,
#                        FILEHANDLE     => $FILEHANDLE,
#                    }
#                );
#            }
#
#            perl_modules(
#                {
#                    parameter_href => $parameter_href,
#                    FILEHANDLE     => $FILEHANDLE,
#                }
#            );
#        }
#    }
#    else {
#
#        if ( $parameter_href->{perl_install} ) {
#
#            install_perl_cpnam(
#                {
#                    parameter_href => $parameter_href,
#                    FILEHANDLE     => $FILEHANDLE,
#                    path           => 1,
#                }
#            );
#        }
#
#        perl_modules(
#            {
#                parameter_href => $parameter_href,
#                FILEHANDLE     => $FILEHANDLE,
#            }
#        );
#    }
#    return;
#}
#
#sub install_perl_cpnam {
#
###install_perl_cpnam
#
###Function : Install perl CPANM
###Returns  : ""
###Arguments: $parameter_href, $FILEHANDLE
###         : $parameter_href => Holds all parameters
###         : $FILEHANDLE     => Filehandle to write to
###         : $path           => Export path if provided {Optional}
#
#    my ($arg_href) = @_;
#
#    ## Default(s)
#    my $path;
#
#    ## Flatten argument(s)
#    my $parameter_href;
#    my $FILEHANDLE;
#
#    my $tmpl = {
#        parameter_href => {
#            required    => 1,
#            defined     => 1,
#            default     => {},
#            strict_type => 1,
#            store       => \$parameter_href
#        },
#        FILEHANDLE => { required => 1, defined => 1, store => \$FILEHANDLE },
#        path       => {
#            default     => 0,
#            allow       => [ 0, 1 ],
#            strict_type => 1,
#            store       => \$path
#        },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    my $pwd = cwd();
#
#    print STDERR 'Writting install instructions for perl and Cpanm', "\n";
#
#    ## Install specific perl version
#    print $FILEHANDLE '### Install specific perl version', "\n";
#
#    ## Move to Home
#    print $FILEHANDLE '## Move to $HOME', "\n";
#    gnu_cd(
#        {
#            directory_path => q?$HOME?,
#            FILEHANDLE     => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    ## Download
#    print $FILEHANDLE '## Download perl', "\n";
#    Program::Download::Wget::wget(
#        {
#            url => 'http://www.cpan.org/src/5.0/perl-'
#              . $parameter_href->{perl_version}
#              . '.tar.gz',
#            FILEHANDLE   => $FILEHANDLE,
#            quiet        => $parameter_href->{quiet},
#            verbose      => $parameter_href->{verbose},
#            outfile_path => 'perl-'
#              . $parameter_href->{perl_version}
#              . '.tar.gz',
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    ## Extract
#    print $FILEHANDLE '## Extract', "\n";
#    print $FILEHANDLE "tar xzf perl-"
#      . $parameter_href->{perl_version}
#      . ".tar.gz";
#    print $FILEHANDLE "\n\n";
#
#    ## Move to perl directory
#    print $FILEHANDLE '## Move to perl directory', "\n";
#    gnu_cd(
#        {
#            directory_path => 'perl-' . $parameter_href->{perl_version},
#            FILEHANDLE     => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    ## Configure
#    print $FILEHANDLE '## Configure', "\n";
#    print $FILEHANDLE './Configure -des -Dprefix=$HOME/perl-'
#      . $parameter_href->{perl_version}, "\n";
#    print $FILEHANDLE 'make', "\n";
#
#    if ( !$parameter_href->{perl_skip_test} ) {
#
#        print $FILEHANDLE 'make test', "\n";
#    }
#    print $FILEHANDLE 'make install', "\n\n";
#
#    if ($path) {
#
#        ## Export path
#        print $FILEHANDLE '## Export path', "\n";
#        print $FILEHANDLE q{echo 'export PATH=$HOME/perl-}
#          . $parameter_href->{perl_version}
#          . q{/:$PATH' >> ~/.bashrc};
#        print $FILEHANDLE "\n\n";
#        print $FILEHANDLE 'export PATH=$HOME/perl-'
#          . $parameter_href->{perl_version}
#          . '/:$PATH';    #Use newly installed perl
#        print $FILEHANDLE "\n\n";
#    }
#
#    ## Remove tar file
#    print $FILEHANDLE '## Remove tar file', "\n";
#    gnu_cd( { FILEHANDLE => $FILEHANDLE, } );
#
#    print $FILEHANDLE '&& ';
#
#    gnu_rm(
#        {
#            infile_path => 'perl-'
#              . $parameter_href->{perl_version}
#              . '.tar.gz',
#            FILEHANDLE => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    ## Move to back
#    print $FILEHANDLE '## Move to original working directory', "\n";
#    gnu_cd(
#        {
#            directory_path => $pwd,
#            FILEHANDLE     => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    print $FILEHANDLE q{echo 'eval `perl -I ~/perl-}
#      . $parameter_href->{perl_version}
#      . q{/lib/perl5/ -Mlocal::lib=~/perl-}
#      . $parameter_href->{perl_version}
#      . q{/`' >> ~/.bash_profile };    #Add at start-up
#    print $FILEHANDLE "\n\n";
#    print $FILEHANDLE
#      q{echo 'export PERL_UNICODE=SAD' >> ~/.bash_profile };    #Add at start-up
#    print $FILEHANDLE "\n\n";
#
#    ## Install perl modules via cpanm
#    print $FILEHANDLE '## Install cpanm', "\n";
#    Program::Download::Wget::wget(
#        {
#            url          => 'http://cpanmin.us',
#            FILEHANDLE   => $FILEHANDLE,
#            quiet        => $parameter_href->{quiet},
#            verbose      => $parameter_href->{verbose},
#            outfile_path => '-',
#        }
#    );
#    print $FILEHANDLE q{ | perl - -l $HOME/perl-}
#      . $parameter_href->{perl_version}
#      . q{/bin App::cpanminus --local-lib=~/perl-}
#      . $parameter_href->{perl_version}
#      . q{/ local::lib };
#    print $FILEHANDLE "\n\n";
#
#    ## Use newly installed perl
#    print $FILEHANDLE q{eval `perl -I ~/perl-}
#      . $parameter_href->{perl_version}
#      . q{/lib/perl5/ -Mlocal::lib=~/perl-}
#      . $parameter_href->{perl_version} . q{/` };
#    print $FILEHANDLE "\n\n";
#
#    ## Use newly installed perl
#    print $FILEHANDLE q{PERL5LIB=~/perl-}
#      . $parameter_href->{perl_version}
#      . q{/lib/perl5};
#    print $FILEHANDLE "\n\n";
#
#    return;
#}
#
#sub perl_modules {
#
###perl_modules
#
###Function : Install perl modules via cpanm
###Returns  : ""
###Arguments: $parameter_href, $FILEHANDLE
###         : $parameter_href => Holds all parameters
###         : $FILEHANDLE     => Filehandle to write to
#
#    my ($arg_href) = @_;
#
#    ## Flatten argument(s)
#    my $parameter_href;
#    my $FILEHANDLE;
#
#    my $tmpl = {
#        parameter_href => {
#            required    => 1,
#            defined     => 1,
#            default     => {},
#            strict_type => 1,
#            store       => \$parameter_href
#        },
#        FILEHANDLE => { required => 1, defined => 1, store => \$FILEHANDLE },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    ## Install perl modules via cpanm
#    print $FILEHANDLE '## Install perl modules via cpanm', "\n";
#    print $FILEHANDLE 'cpanm ';
#
#    if ( $parameter_href->{perl_modules_force} ) {
#
#        print $FILEHANDLE '--force ';
#    }
#    print $FILEHANDLE join( q{ }, @{ $parameter_href->{perl_modules} } ) . q{ };
#    print $FILEHANDLE "\n\n";
#
#    return;
#}

#sub remove_install_dir {
#
###remove_install_dir
#
###Function : Remove the temporary install directory
###Returns  : ""
###Arguments: $FILEHANDLE, $pwd, $install_directory
###         : $FILEHANDLE        => FILEHANDLE to write to
###         : $pwd               => The original working directory
###         : $install_directory => Temporary installation directory
#
#    my ($arg_href) = @_;
#
#    ## Default(s)
#    my $install_directory;
#
#    ## Flatten argument(s)
#    my $FILEHANDLE;
#    my $pwd;
#
#    my $tmpl = {
#        FILEHANDLE => { required => 1, defined => 1, store => \$FILEHANDLE },
#        pwd =>
#          { required => 1, defined => 1, strict_type => 1, store => \$pwd },
#        install_directory => {
#            default     => '.MIP',
#            allow       => qr/^\.\S+$/,
#            strict_type => 1,
#            store       => \$install_directory
#        },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    ## Go back to subroutine origin
#    print $FILEHANDLE '## Moving back to original working directory', "\n";
#    gnu_cd(
#        {
#            directory_path => $pwd,
#            FILEHANDLE     => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    ## Clean up
#    print $FILEHANDLE '## Clean up', "\n";
#    gnu_rm(
#        {
#            infile_path => $install_directory,
#            force       => 1,
#            recursive   => 1,
#            FILEHANDLE  => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    return;
#}
#
#sub create_install_dir {
#
###create_install_dir
#
###Function : Create the temporary install directory
###Returns  : ""
###Arguments: $FILEHANDLE, $install_directory
###         : $FILEHANDLE        => FILEHANDLE to write to
###         : $install_directory => Temporary installation directory
#
#    my ($arg_href) = @_;
#
#    ## Default(s)
#    my $install_directory;
#
#    ## Flatten argument(s)
#    my $FILEHANDLE;
#
#    my $tmpl = {
#        FILEHANDLE => { required => 1, defined => 1, store => \$FILEHANDLE },
#        install_directory => {
#            default     => '.MIP',
#            strict_type => 1,
#            store       => \$install_directory
#        },
#    };
#
#    check( $tmpl, $arg_href, 1 ) or croak qw[Could not parse arguments!];
#
#    ## Create temp install directory
#    print $FILEHANDLE '## Create temp install directory', "\n";
#    gnu_mkdir(
#        {
#            indirectory_path => $install_directory,
#            parents          => 1,
#            FILEHANDLE       => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    gnu_cd(
#        {
#            directory_path => $install_directory,
#            FILEHANDLE     => $FILEHANDLE,
#        }
#    );
#    print $FILEHANDLE "\n\n";
#
#    return;
#}
#
