# Bugs

- ue sync may be triggering too often
  ex:

```bash
Updating 8c43bcf6..9dcce75d
Fast-forward
 .mcp.json                                                    | 10 ++++++++++
 CPP_Tests.uproject                                           | 12 ++++++++++--
 Content/Blueprints/NPCs/BaseNPCs/BP_NPC_Base.uasset          |  4 ++--
 .../John/Lvl_FirstPerson/0/NI/0EQA6S4EME05LRSHIFJ0CD.uasset  |  3 ---
 .../John/Lvl_FirstPerson/6/C2/MW5V1QGLJ6EF709YB8J1AF.uasset  |  4 ++--
 .../John/Lvl_FirstPerson/6/MD/9FB86BECVFNBNQIIW0OKL7.uasset  |  4 ++--
 .../John/Lvl_FirstPerson/6/P0/FZCZ09PRYUX5UMNLLPA4KQ.uasset  |  4 ++--
 .../John/Lvl_FirstPerson/7/JS/2ENRP2JNUOK0NTFP8AB1W6.uasset  |  4 ++--
 .../John/Lvl_FirstPerson/D/1P/IA6IDHUJX3QF7MCYFCV88E.uasset  |  4 ++--
 .../John/Lvl_FirstPerson/D/CM/W4TDNBGY2RVV55HO6DMO6Q.uasset  |  4 ++--
 Source/CPP_Tests.Target.cs                                   |  4 ++--
 Source/CPP_TestsEditor.Target.cs                             |  4 ++--
 12 files changed, 38 insertions(+), 23 deletions(-)
 create mode 100644 .mcp.json
 delete mode 100644 Content/__ExternalActors__/Maps/Dev/John/Lvl_FirstPerson/0/NI/0EQA6S4EME05LRSHIFJ0CD.uasset

This triggered a rebuild. NOTE: this is on a old version of ue sync. MUST VERIFY its not an issue in most uptodate version.
- domain-key for new domains in domains.json are not created properly
  ex: DomainName dir should be -> domain-name, but is just dir name DomainName
```

- Hide From site feature only hides. Then state is broken on reload and it says hide from site again instead of Show in site.
- Generated Index sections are broken.
