# Migration Step 18: Linked Server Connectivity Alternatives for Azure SQL MI

## Overview

Azure SQL Managed Instance supports linked servers but the underlying network topology changes significantly compared to on-premises SQL Server. This document describes the available connectivity patterns, their trade-offs, and guidance for choosing the right approach for each Lakeview Medical Center external system.

---

## Current Linked Server Inventory

| Linked Server | On-Prem Target | Target Type | Migration Path |
|---|---|---|---|
| PHARMACY_SERVER | PHARM-SQL-01.lakeviewmedical.local | SQL Server | Azure SQL DB + Private Endpoint |
| INSURANCE_CLEARINGHOUSE | CLH-SQL-01.clearinghouse.local | SQL Server | Azure SQL DB + Private Endpoint |
| LAB_SYSTEM | LAB-SQL-01.lakeviewmedical.local | SQL Server | Azure SQL DB + VNet Peering |
| RADIOLOGY_PACS | PACS-ORA-01.lakeviewmedical.local | Oracle | Azure Relay Hybrid Connection |

---

## Connectivity Patterns

### 1. Private Endpoints

**Best for:** Azure SQL MI connecting to other Azure PaaS services (Azure SQL Database, Cosmos DB, Azure Storage) within or across subscriptions.

**How it works:**
- A private endpoint creates a network interface inside the MI's VNet with a private IP address.
- Traffic stays entirely within the Azure backbone network — never traverses the public internet.
- DNS resolution maps the `*.privatelink.database.windows.net` FQDN to the private IP.

**Configuration steps:**
1. Create a private endpoint for the target Azure SQL Database in the MI's VNet (or a peered VNet).
2. Configure Private DNS Zone (`privatelink.database.windows.net`) linked to the MI's VNet.
3. Use the `*.privatelink.database.windows.net` FQDN as the `@datasrc` in `sp_addlinkedserver`.
4. Disable public network access on the target to enforce private-only connectivity.

**Advantages:**
- Lowest latency for Azure-to-Azure communication
- No data exfiltration risk — traffic stays on Microsoft backbone
- No firewall rules needed — network-level isolation
- Supports all SQL Server authentication methods

**Limitations:**
- Only works for targets that support Private Link (most Azure PaaS services do)
- Additional cost for the private endpoint resource (~$7.30/month + data processing)
- DNS configuration required in each VNet

**Recommended for:** PHARMACY_SERVER, INSURANCE_CLEARINGHOUSE

---

### 2. VNet Peering

**Best for:** Azure SQL MI connecting to services deployed in IaaS VMs or other managed instances in different VNets.

**How it works:**
- VNet peering establishes a direct, low-latency network path between two Azure VNets.
- Supports both same-region and cross-region (global) peering.
- Once peered, resources in each VNet can communicate via private IP addresses.

**Configuration steps:**
1. Create a VNet peering between the MI's VNet and the target service's VNet.
2. Ensure no IP address space overlap between VNets.
3. Enable "Allow gateway transit" if the target VNet uses a VPN gateway.
4. Use the target's private IP or internal FQDN as `@datasrc`.

**Advantages:**
- Very low latency (same as being in the same VNet)
- No bandwidth bottleneck — uses Azure backbone at network speed
- No additional gateway infrastructure needed
- Works for any IP-accessible service (SQL Server VMs, PostgreSQL, MySQL, custom apps)

**Limitations:**
- Cannot peer VNets with overlapping IP ranges
- Global peering has higher data transfer costs
- Max 500 peerings per VNet
- Does not work for on-premises resources without additional gateway

**Recommended for:** LAB_SYSTEM (if migrated to Azure SQL DB or VM in a separate VNet)

---

### 3. Azure Relay Hybrid Connections

**Best for:** Azure SQL MI connecting to systems that remain on-premises or in third-party data centers.

**How it works:**
- Azure Relay provides a cloud-hosted rendezvous point.
- An on-premises Hybrid Connection Manager (HCM) agent establishes an outbound connection to Azure Relay.
- Azure SQL MI connects to the relay endpoint; the relay bridges traffic to the on-premises system.
- No inbound firewall ports required on the on-premises network.

**Configuration steps:**
1. Create an Azure Relay namespace and Hybrid Connection in the Azure portal.
2. Install the Hybrid Connection Manager on a server in the on-premises network that can reach the target.
3. Configure the HCM to listen for connections to the target host:port.
4. Use the relay namespace FQDN (`*.servicebus.windows.net`) as the linked server `@datasrc`.

**Advantages:**
- No inbound firewall rules — HCM uses outbound HTTPS (port 443)
- Works through corporate firewalls and NAT
- Quick to set up for proof-of-concept
- Good for systems that cannot be migrated to Azure yet

**Limitations:**
- Higher latency than direct connectivity (relay hop adds 10–50ms)
- Throughput limited to ~200 Mbps per connection
- HCM agent must be maintained on-premises
- Not suitable for high-volume or latency-sensitive workloads
- Additional Azure Relay costs

**Recommended for:** RADIOLOGY_PACS (Oracle system remaining on-premises during phased migration)

---

### 4. Site-to-Site VPN

**Best for:** Broad hybrid connectivity when many on-premises systems need to be reachable from Azure.

**How it works:**
- An IPsec/IKE VPN tunnel connects the on-premises network to the Azure VNet.
- All traffic between the VNet and on-premises flows through the encrypted tunnel.
- Azure SQL MI can reach any on-premises server via private IP.

**Configuration steps:**
1. Deploy an Azure VPN Gateway in the MI's VNet (or a hub VNet peered to it).
2. Configure the on-premises VPN device with the Azure gateway's public IP.
3. Establish the tunnel and configure routing (BGP recommended).
4. Use on-premises server IP addresses directly as `@datasrc`.

**Advantages:**
- Encrypted tunnel at the network layer
- Reach any on-premises IP without per-service configuration
- Supports all protocols, not just HTTP/TCP 443
- Well-understood technology with wide device support

**Limitations:**
- VPN gateway has bandwidth limits (up to 10 Gbps for VpnGw5)
- Latency depends on internet path quality
- Gateway costs ($0.04–$1.15/hr depending on SKU)
- Requires on-premises VPN device and network team coordination

**Recommended for:** RADIOLOGY_PACS (alternative to Azure Relay if broader on-prem access is needed)

---

### 5. Azure ExpressRoute

**Best for:** Enterprise-grade, high-bandwidth, low-latency hybrid connectivity with SLA-backed performance.

**How it works:**
- A dedicated private connection between the on-premises network and Azure, provisioned through a connectivity provider.
- Does not traverse the public internet.
- Can be combined with ExpressRoute Private Peering to reach MI's VNet.

**Configuration steps:**
1. Provision an ExpressRoute circuit through a connectivity provider.
2. Configure private peering with the MI's VNet.
3. Use on-premises IP addresses directly as `@datasrc`.

**Advantages:**
- Lowest and most predictable latency
- Bandwidth from 50 Mbps to 100 Gbps
- SLA-backed availability (99.95%+)
- Supports all protocols

**Limitations:**
- Highest cost option (circuit + provider fees)
- Longer provisioning time (days to weeks)
- Requires coordination with a connectivity provider
- Overkill if only a few systems remain on-premises

**Recommended for:** Organizations with existing ExpressRoute circuits or high-volume hybrid workloads.

---

### 6. Replace Linked Servers Entirely (Long-Term)

**Best for:** Eliminating linked server dependencies during application modernization.

Linked servers introduce tight coupling, distributed transaction complexity, and network dependency. Consider replacing them with modern integration patterns:

| Pattern | Use Case | Tools |
|---|---|---|
| **REST APIs** | Real-time lookups (drug info, eligibility) | Azure API Management, Azure Functions |
| **Event-driven messaging** | Async data sync (lab results, claims) | Azure Service Bus, Event Grid |
| **ETL / data pipelines** | Batch data synchronization | Azure Data Factory, Synapse Pipelines |
| **Managed identity auth** | Eliminate SQL credentials | Azure AD (Entra ID) managed identities |
| **FHIR APIs** | Healthcare interoperability standard | Azure Health Data Services |

**Modernization roadmap for Lakeview Medical Center:**

1. **Phase 1 (Current):** Reconfigure linked servers with cloud endpoints (Step 16).
2. **Phase 2:** Build API wrappers around pharmacy and insurance queries using Azure Functions.
3. **Phase 3:** Replace OPENQUERY calls with REST API calls via `sp_invoke_external_rest_endpoint` (available on MI).
4. **Phase 4:** Migrate PACS integration to FHIR-based imaging APIs.
5. **Phase 5:** Decommission all linked servers.

---

## Decision Matrix

| Criteria | Private Endpoint | VNet Peering | Azure Relay | S2S VPN | ExpressRoute |
|---|:---:|:---:|:---:|:---:|:---:|
| Target in Azure PaaS | ✅ Best | ⚠️ N/A | ❌ | ❌ | ❌ |
| Target in Azure IaaS VM | ✅ | ✅ Best | ❌ | ❌ | ❌ |
| Target on-premises | ❌ | ❌ | ✅ Good | ✅ Best | ✅ Best |
| Latency | <1ms | <1ms | 10–50ms | 5–30ms | 1–5ms |
| Bandwidth | High | High | ~200 Mbps | Up to 10 Gbps | Up to 100 Gbps |
| Firewall changes needed | No | No | No (outbound 443) | Yes (IPsec) | No |
| Monthly cost (approx.) | ~$10 | Free | ~$10–50 | ~$130–830 | ~$200–5000+ |
| Setup complexity | Low | Low | Medium | Medium | High |

---

## Recommendations for Lakeview Medical Center

| System | Short-Term (Cutover) | Long-Term (Modernization) |
|---|---|---|
| **Pharmacy** | Private Endpoint linked server | REST API via Azure Functions + `sp_invoke_external_rest_endpoint` |
| **Insurance** | Private Endpoint linked server | Event-driven claims via Service Bus |
| **Lab System** | VNet Peering linked server | FHIR API integration via Azure Health Data Services |
| **Radiology PACS** | Azure Relay Hybrid Connection | DICOMweb / FHIR ImagingStudy API |

---

## References

- [Azure SQL MI Linked Servers](https://learn.microsoft.com/en-us/azure/azure-sql/managed-instance/linked-servers-transact-sql)
- [Private Link for Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/private-endpoint-overview)
- [VNet Peering](https://learn.microsoft.com/en-us/azure/virtual-network/virtual-network-peering-overview)
- [Azure Relay Hybrid Connections](https://learn.microsoft.com/en-us/azure/azure-relay/relay-hybrid-connections-protocol)
- [sp_invoke_external_rest_endpoint](https://learn.microsoft.com/en-us/sql/relational-databases/system-stored-procedures/sp-invoke-external-rest-endpoint-transact-sql)
- [Azure Health Data Services - FHIR](https://learn.microsoft.com/en-us/azure/healthcare-apis/fhir/overview)
