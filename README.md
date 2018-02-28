# Koha Batch Permissions Modifier plugin

This plugin allows librarians to use arbitrary patron accounts as 'templates' for setting the user permissions of other patrons via patron lists. It can be used interactively, or automatically ( using a template to patron list mapping ).

When used in automatic mode, the patrons in the list will have their permissions updated when
* A patron is added to a list
* A list patron's permissions are updated ( i.e. you cannot alter a patrons permissions, the permissions will be reset )
* The template patron's permissions are updated

# Introduction

Koha’s Plugin System (available in Koha 3.12+) allows for you to add additional tools and reports to [Koha](http://koha-community.org) that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work. Learn more about the Koha Plugin System in the [Koha 3.22 Manual](http://manual.koha-community.org/3.22/en/pluginsystem.html) or watch [Kyle’s tutorial video](http://bywatersolutions.com/2013/01/23/koha-plugin-system-coming-soon/).

# Downloading

From the [release page](https://github.com/bywatersolutions/koha-plugin-batch-permissions-modifier/releases) you can download the relevant *.kpz file

# Installing

Koha's Plugin System allows for you to add additional tools and reports to Koha that are specific to your library. Plugins are installed by uploading KPZ ( Koha Plugin Zip ) packages. A KPZ file is just a zip file containing the perl files, template files, and any other files necessary to make the plugin work.

The plugin system needs to be turned on by a system administrator.

To set up the Koha plugin system you must first make some changes to your install.

* Change `<enable_plugins>0<enable_plugins>` to `<enable_plugins>1</enable_plugins>` in your koha-conf.xml file
* Confirm that the path to `<pluginsdir>` exists, is correct, and is writable by the web server
* Restart your webserver
* Restart memcached if you are using it

Once set up is complete you will need to alter your UseKohaPlugins system preference. On the Tools page you will see the Tools Plugins and on the Reports page you will see the Reports Plugins.

# Setup

* Install the plugin
* Run the plugin configurator

This plugin has to configuration fields:
* Template Patrons: this is a list of patron accounts that you want to use as templates. That is, we will apply the current user permissions from these patrons to other patrons.
* Template permission mappings: This is a list of borrowernumber:patron_list_id pairs that will automate the setting of user permissions. If a patron is added to the given list, his or her permissions will be set to match those of the patron with the given borrowernumber. This section is optional and not necessary if you will only be using the plugin interactively.
