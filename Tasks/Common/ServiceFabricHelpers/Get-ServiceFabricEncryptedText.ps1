# Note: Connect-ServiceFabricClusterFromServiceEndpoint must be called prior to invoking this function. That function properly initializes
# the values in the cluster connection parameters that this function uses.
function Get-ServiceFabricEncryptedText
{
    Param (
        [String]
        $Text,

        [Hashtable]
        $ClusterConnectionParameters
    )

    $defaultCertStoreName = "My"
    $defaultCertStoreLocation = "CurrentUser"

    if ($ClusterConnectionParameters["ServerCertThumbprint"])
    {
        $serverCertThumbprints = $ClusterConnectionParameters["ServerCertThumbprint"];
    }
    else 
    {
        try
        {
            $manifest = [xml](Get-ServiceFabricClusterManifest)
            $securityInfo = $manifest.ClusterManifest.FabricSettings.Section | Where-Object {$_.Name -eq 'Security'}
            $serverCertsParameter = $securityInfo.Parameter | Where-Object { $_.Name -eq 'ServerCertThumbprints' }
            $serverCertThumbprints = $serverCertsParameter.Value.Split(',').trim()
        }
        catch 
        {
            if ($clusterConnectionParameters["ServerCommonName"])
            {
                $serverCertValues = $ClusterConnectionParameters["ServerCommonName"]
                
                # Get server cert thumbprints of valid certificates
                if ($serverCertValues -is [array])
                {
                    foreach ($serverCertValue in $serverCertValues)
                    {
                        $serverCerts = Get-ChildItem -Path "Cert:\$defaultCertStoreLocation\$defaultCertStoreName" | Where-Object {$_.Subject -like $serverCertValue -and ($_.NotAfter -gt (Get-Date))}

                        if ($serverCerts -is [array] -and $serverCerts.Length -gt 1) 
                        {
                            Write-Warning (Get-VstsLocString -Key MultipleCertPresentInLocalStoreWarningMsg -ArgumentList $serverCertValue)
                            break
                        }
                        else 
                        {
                            $serverCertThumbprints = $serverCerts.Thumbprint
                            if ($serverCertThumbprints)
                            {
                                break
                            }
                        }
                    }
                }
                else
                {
                    $serverCertThumbprints = (Get-ChildItem -Path "Cert:\$defaultCertStoreLocation\$defaultCertStoreName" | Where-Object {$_.Subject -like $serverCertValues}).Thumbprint
                }
            }
        }
    }

    if ($serverCertThumbprints -is [array])
    {
        foreach ($serverCertThumbprint in $serverCertThumbprints)
        {
            $cert = Get-Item "Cert:\$defaultCertStoreLocation\$defaultCertStoreName\$serverCertThumbprint" -ErrorAction SilentlyContinue
            if ($cert)
            {
                break
            }
        }
    }
    else
    {
        $cert = Get-Item "Cert:\$defaultCertStoreLocation\$defaultCertStoreName\$serverCertThumbprints" -ErrorAction SilentlyContinue
    }

    if (-not $cert)
    {
        Write-Warning (Get-VstsLocString -Key ServerCertificateNotFoundForTextEncrypt -ArgumentList $serverCertThumbprints)
        return $null
    }

    # Encrypt the text using the cluster connection's certificate.
    $global:operationId = $SF_Operations.EncryptServiceFabricText
    return Invoke-ServiceFabricEncryptText -Text $Text -CertStore -CertThumbprint $cert.Thumbprint -StoreName $defaultCertStoreName -StoreLocation $defaultCertStoreLocation
}