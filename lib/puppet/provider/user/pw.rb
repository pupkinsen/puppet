require 'puppet/provider/nameservice/pw'
require 'open3'

Puppet::Type.type(:user).provide :pw, :parent => Puppet::Provider::NameService::PW do
  desc "User management via `pw` on FreeBSD and DragonFly BSD."

  commands :pw => "pw"
  has_features :manages_homedir, :allows_duplicates, :manages_passwords, :manages_expiry, :manages_shell, :manages_loginclass

  defaultfor :operatingsystem => [:freebsd, :dragonfly]
  confine    :operatingsystem => [:freebsd, :dragonfly]

  options :home, :flag => "-d", :method => :dir
  options :comment, :method => :gecos
  options :groups, :flag => "-G"
  options :loginclass, :flag => '-L'
  options :expiry, :method => :expire, :munge => proc { |value|
    value = '0000-00-00' if value == :absent
    value.split("-").reverse.join("-")
  }


  verify :gid, "GID must be an integer" do |value|
    value.is_a? Integer
  end

  verify :groups, "Groups must be comma-separated" do |value|
    value !~ /\s/
  end

  def addcmd
    cmd = [command(:pw), "useradd", @resource[:name]]
    @resource.class.validproperties.each do |property|
      next if property == :ensure or property == :password
      if value = @resource.should(property) and value != ""
        cmd << flag(property) << munge(property,value)
      end
    end

    cmd << "-o" if @resource.allowdupe?
    cmd << "-m" if @resource.managehome?
    cmd
  end

  def modifycmd(param, value)
    if param == :expiry
      # FreeBSD uses DD-MM-YYYY rather than YYYY-MM-DD
      value = value.split("-").reverse.join("-")
    end
    cmd = super(param, value)
    cmd << "-m" if @resource.managehome?
    cmd
  end

  def deletecmd
    cmd = super
    cmd << "-r" if @resource.managehome?
    cmd
  end

  def create
    super

    # Set the password after create if given
    self.password = @resource[:password] if @resource[:password]
  end

  def getpwdata(position)
    userline = `#{command(:pw)} user show #{@resource[:name]}`
    userdata = userline.chomp.split(':') if userline
    data = userdata[position] if position < userdata.length 
    data
  end
  
  # use pw to update password hash
  def password=(cryptopw)
    Puppet.debug "change password for user '#{@resource[:name]}' method called with hash '#{cryptopw}'"
    stdin, stdout, stderr = Open3.popen3("pw user mod #{@resource[:name]} -H 0")
    stdin.puts(cryptopw)
    stdin.close
    Puppet.debug "finished password for user '#{@resource[:name]}' method called with hash '#{cryptopw}'"
  end
    
  def loginclass
    Puppet.debug "checking login class for user '#{@resource[:name]}' method called"
    current_loginclass = getpwdata(4)
    Puppet.debug "finished login class for user '#{@resource[:name]}' method called : '#{current_loginclass}'"
    current_loginclass
  end

  # get password from /etc/master.passwd
  def password
    Puppet.debug "checking password for user '#{@resource[:name]}' method called"
    current_password = getpwdata(1)
    Puppet.debug "finished password for user '#{@resource[:name]}' method called : '#{current_password}'"
    current_password
  end

  # Get expiry from system and convert to Puppet-style date
  def expiry
    expiry = self.get(:expiry)
    expiry = :absent if expiry == 0

    if expiry != :absent
      t = Time.at(expiry)
      expiry = "%4d-%02d-%02d" % [t.year, t.month, t.mday]
    end

    expiry
  end
end

