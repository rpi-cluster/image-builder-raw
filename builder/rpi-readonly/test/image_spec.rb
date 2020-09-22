require 'serverspec'
set :backend, :exec

describe "Raw Image" do
  let(:image_path) { return '/rpi-raw.img' }

  it "exists" do
    image_file = file(image_path)
    expect(image_file).to exist
  end

  context "Partition table" do
    let(:stdout) { command("fdisk -l #{image_path} | grep '^/rpi-raw'").stdout }

    it "has 3 partitions" do
      partitions = stdout.split(/\r?\n/)
      expect(partitions.size).to be 3
    end

    it "has a boot-partition with a sda1 W95 FAT32 filesystem" do
      expect(stdout).to contain('^.*\.img1 \* .*W95 FAT32 \(LBA\)$')
    end

    it "has a root-partition with a sda2 Linux filesystem" do
      expect(stdout).to contain('^.*\.img2 .*Linux$')
    end
    
    it "has a data-partition with a sda3 Linux filesystem" do
      expect(stdout).to contain('^.*\.img3 .*Linux$')
    end

    it "partition sda1 starts at sector 2048" do
      expect(stdout).to contain('^.*\.img1\ \* *2048 .*$')
    end

    it "partition sda1 has a size of 100M" do
      expect(stdout).to contain('^.*\.img1.* 100M  c.*$')
    end
  end
end
