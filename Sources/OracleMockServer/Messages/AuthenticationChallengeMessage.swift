//===----------------------------------------------------------------------===//
//
// This source file is part of the OracleNIO open source project
//
// Copyright (c) 2025 Timo Zacherl and the OracleNIO project authors
// Licensed under Apache License v2.0
//
// See LICENSE for license information
// See CONTRIBUTORS.md for the list of OracleNIO project authors
//
// SPDX-License-Identifier: Apache-2.0
//
//===----------------------------------------------------------------------===//

import NIOCore

struct AuthenticationChallengeMessage: ServerMessage {
    func serialize() throws -> ByteBuffer {
        try ByteBuffer(
            plainHexEncodedBytes: """
                00 00 0D 17 06 00 00 00
                20 00 01 06 00 78 38 36
                5F 36 34 2F 4C 69 6E 75
                78 20 32 2E 34 2E 78 78
                00 69 03 23 0A 00 66 03
                40 03 01 40 03 66 03 01
                66 03 48 03 01 48 03 66
                03 01 66 03 52 03 01 52
                03 66 03 01 66 03 61 03
                01 61 03 66 03 01 66 03
                1F 03 08 1F 03 66 03 01
                00 64 00 00 00 60 01 24
                0F 05 0B 0C 03 0C 0C 05
                04 05 0D 06 09 07 08 05
                05 05 05 05 0F 05 05 05
                05 05 0A 05 05 05 05 05
                04 05 06 07 08 08 23 47
                23 47 08 11 23 08 11 41
                B0 47 00 83 03 69 07 D0
                03 00 00 00 00 00 00 00
                00 00 00 00 00 00 00 00
                00 00 00 00 00 00 00 00
                00 00 00 00 00 00 00 00
                00 00 00 00 00 00 35 06
                01 01 01 EF 0F 01 18 01
                01 01 01 01 01 01 7F FF
                03 10 03 03 01 01 FF 01
                FF FF 01 0C 01 01 FF 01
                06 0C F6 09 7F 05 0F FF
                0D 0B 00 1F 00 00 00 00
                00 00 0C 01 0C 02 01 00
                01 18 00 7F 01 00 00 00
                00 02 00 01 00 01 00 01
                00 00 00 02 00 02 00 0A
                00 00 00 08 00 08 00 01
                00 00 00 0C 00 0C 00 0A
                00 00 00 17 00 17 00 01
                00 00 00 18 00 18 00 01
                00 00 00 19 00 19 00 01
                00 00 00 1A 00 1A 00 01
                00 00 00 1B 00 1B 00 0A
                00 00 00 1C 00 1C 00 01
                00 00 00 1D 00 1D 00 01
                00 00 00 1E 00 1E 00 01
                00 00 00 1F 00 1F 00 01
                00 00 00 20 00 20 00 01
                00 00 00 21 00 21 00 01
                00 00 00 0A 00 0A 00 01
                00 00 00 0B 00 0B 00 01
                00 00 00 28 00 28 00 01
                00 00 00 29 00 29 00 01
                00 00 00 75 00 75 00 01
                00 00 00 78 00 78 00 01
                00 00 01 22 01 22 00 01
                00 00 01 23 01 23 00 01
                00 00 01 24 01 24 00 01
                00 00 01 25 01 25 00 01
                00 00 01 26 01 26 00 01
                00 00 01 2A 01 2A 00 01
                00 00 01 2B 01 2B 00 01
                00 00 01 2C 01 2C 00 01
                00 00 01 2D 01 2D 00 01
                00 00 01 2E 01 2E 00 01
                00 00 01 2F 01 2F 00 01
                00 00 01 31 01 31 00 01
                00 00 01 32 01 32 00 01
                00 00 01 33 01 33 00 01
                00 00 01 34 01 34 00 01
                00 00 01 35 01 35 00 01
                00 00 01 36 01 36 00 01
                00 00 01 37 01 37 00 01
                00 00 01 38 01 38 00 01
                00 00 01 39 01 39 00 01
                00 00 01 3B 01 3B 00 01
                00 00 01 3C 01 3C 00 01
                00 00 01 3D 01 3D 00 01
                00 00 01 3E 01 3E 00 01
                00 00 01 3F 01 3F 00 01
                00 00 01 40 01 40 00 01
                00 00 01 41 01 41 00 01
                00 00 01 42 01 42 00 01
                00 00 01 43 01 43 00 01
                00 00 01 47 01 47 00 01
                00 00 01 48 01 48 00 01
                00 00 01 49 01 49 00 01
                00 00 01 4B 01 4B 00 01
                00 00 01 4D 01 4D 00 01
                00 00 01 53 01 53 00 01
                00 00 01 54 01 54 00 01
                00 00 01 55 01 55 00 01
                00 00 01 56 01 56 00 01
                00 00 01 57 01 57 00 01
                00 00 01 58 01 58 00 01
                00 00 01 59 01 59 00 01
                00 00 01 5A 01 5A 00 01
                00 00 01 5C 01 5C 00 01
                00 00 01 5D 01 5D 00 01
                00 00 01 62 01 62 00 01
                00 00 01 63 01 63 00 01
                00 00 01 67 01 67 00 01
                00 00 01 6B 01 6B 00 01
                00 00 01 7C 01 7C 00 01
                00 00 01 7D 01 7D 00 01
                00 00 01 7E 01 7E 00 01
                00 00 01 80 01 80 00 01
                00 00 01 81 01 81 00 01
                00 00 01 82 01 82 00 01
                00 00 01 83 01 83 00 01
                00 00 01 84 01 84 00 01
                00 00 01 85 01 85 00 01
                00 00 01 86 01 86 00 01
                00 00 01 87 01 87 00 01
                00 00 01 89 01 89 00 01
                00 00 01 8A 01 8A 00 01
                00 00 01 8B 01 8B 00 01
                00 00 01 8C 01 8C 00 01
                00 00 01 8D 01 8D 00 01
                00 00 01 8E 01 8E 00 01
                00 00 01 8F 01 8F 00 01
                00 00 01 90 01 90 00 01
                00 00 01 91 01 91 00 01
                00 00 01 94 01 94 00 01
                00 00 01 95 01 95 00 01
                00 00 01 96 01 96 00 01
                00 00 01 97 01 97 00 01
                00 00 01 9D 01 9D 00 01
                00 00 01 9E 01 9E 00 01
                00 00 01 9F 01 9F 00 01
                00 00 01 A0 01 A0 00 01
                00 00 01 A1 01 A1 00 01
                00 00 01 A2 01 A2 00 01
                00 00 01 A3 01 A3 00 01
                00 00 01 A4 01 A4 00 01
                00 00 01 A5 01 A5 00 01
                00 00 01 A6 01 A6 00 01
                00 00 01 A7 01 A7 00 01
                00 00 01 A8 01 A8 00 01
                00 00 01 A9 01 A9 00 01
                00 00 01 AA 01 AA 00 01
                00 00 01 AB 01 AB 00 01
                00 00 01 AD 01 AD 00 01
                00 00 01 AE 01 AE 00 01
                00 00 01 AF 01 AF 00 01
                00 00 01 B0 01 B0 00 01
                00 00 01 B1 01 B1 00 01
                00 00 01 C1 01 C1 00 01
                00 00 01 C2 01 C2 00 01
                00 00 01 C6 01 C6 00 01
                00 00 01 C7 01 C7 00 01
                00 00 01 C8 01 C8 00 01
                00 00 01 C9 01 C9 00 01
                00 00 01 CA 01 CA 00 01
                00 00 01 CB 01 CB 00 01
                00 00 01 CC 01 CC 00 01
                00 00 01 CD 01 CD 00 01
                00 00 01 CE 01 CE 00 01
                00 00 01 CF 01 CF 00 01
                00 00 01 D2 01 D2 00 01
                00 00 01 D3 01 D3 00 01
                00 00 01 D4 01 D4 00 01
                00 00 01 D5 01 D5 00 01
                00 00 01 D6 01 D6 00 01
                00 00 01 D7 01 D7 00 01
                00 00 01 D8 01 D8 00 01
                00 00 01 D9 01 D9 00 01
                00 00 01 DA 01 DA 00 01
                00 00 01 DB 01 DB 00 01
                00 00 01 DC 01 DC 00 01
                00 00 01 DD 01 DD 00 01
                00 00 01 DE 01 DE 00 01
                00 00 01 DF 01 DF 00 01
                00 00 01 E0 01 E0 00 01
                00 00 01 E1 01 E1 00 01
                00 00 01 E2 01 E2 00 01
                00 00 01 E3 01 E3 00 01
                00 00 01 E4 01 E4 00 01
                00 00 01 E5 01 E5 00 01
                00 00 01 E6 01 E6 00 01
                00 00 01 EA 01 EA 00 01
                00 00 01 EB 01 EB 00 01
                00 00 01 EC 01 EC 00 01
                00 00 01 ED 01 ED 00 01
                00 00 01 EE 01 EE 00 01
                00 00 01 EF 01 EF 00 01
                00 00 01 F0 01 F0 00 01
                00 00 01 F2 01 F2 00 01
                00 00 01 F3 01 F3 00 01
                00 00 01 F4 01 F4 00 01
                00 00 01 F5 01 F5 00 01
                00 00 01 F6 01 F6 00 01
                00 00 01 FD 01 FD 00 01
                00 00 01 FE 01 FE 00 01
                00 00 02 01 02 01 00 01
                00 00 02 02 02 02 00 01
                00 00 02 04 02 04 00 01
                00 00 02 05 02 05 00 01
                00 00 02 06 02 06 00 01
                00 00 02 07 02 07 00 01
                00 00 02 08 02 08 00 01
                00 00 02 09 02 09 00 01
                00 00 02 0A 02 0A 00 01
                00 00 02 0B 02 0B 00 01
                00 00 02 0C 02 0C 00 01
                00 00 02 0D 02 0D 00 01
                00 00 02 0E 02 0E 00 01
                00 00 02 0F 02 0F 00 01
                00 00 02 10 02 10 00 01
                00 00 02 11 02 11 00 01
                00 00 02 12 02 12 00 01
                00 00 02 13 02 13 00 01
                00 00 02 14 02 14 00 01
                00 00 02 15 02 15 00 01
                00 00 02 16 02 16 00 01
                00 00 02 17 02 17 00 01
                00 00 02 18 02 18 00 01
                00 00 02 19 02 19 00 01
                00 00 02 1A 02 1A 00 01
                00 00 02 1B 02 1B 00 01
                00 00 02 1F 02 1F 00 01
                00 00 02 20 00 00 02 21
                00 00 02 22 00 00 02 23
                00 00 02 24 00 00 02 25
                00 00 02 26 00 00 02 27
                00 00 02 28 00 00 02 29
                00 00 02 2A 00 00 02 2B
                00 00 02 2C 00 00 02 2D
                00 00 02 2E 00 00 02 2F
                00 00 02 30 02 30 00 01
                00 00 02 31 00 00 02 32
                00 00 02 33 02 33 00 01
                00 00 02 34 02 34 00 01
                00 00 02 36 00 00 02 37
                00 00 02 38 00 00 02 39
                00 00 02 3A 00 00 02 3B
                00 00 02 3C 02 3C 00 01
                00 00 02 3D 02 3D 00 01
                00 00 02 3E 02 3E 00 01
                00 00 02 3F 02 3F 00 01
                00 00 02 40 02 40 00 01
                00 00 02 41 00 00 02 42
                02 42 00 01 00 00 02 43
                02 43 00 01 00 00 02 44
                02 44 00 01 00 00 02 45
                02 45 00 01 00 00 02 46
                02 46 00 01 00 00 02 47
                02 47 00 01 00 00 02 48
                02 48 00 01 00 00 02 49
                02 49 00 01 00 00 02 4A
                00 00 02 4B 00 00 02 4C
                00 00 02 4D 00 00 02 4E
                02 4E 00 01 00 00 02 4F
                02 4F 00 01 00 00 02 50
                02 50 00 01 00 00 02 51
                02 51 00 01 00 00 02 52
                02 52 00 01 00 00 02 53
                02 53 00 01 00 00 02 54

                02 54 00 01 00 00 02 55
                02 55 00 01 00 00 02 56
                02 56 00 01 00 00 02 57
                02 57 00 01 00 00 02 58
                02 58 00 01 00 00 02 59
                02 59 00 01 00 00 02 5A
                02 5A 00 01 00 00 02 5B
                02 5B 00 01 00 00 02 5C
                02 5C 00 01 00 00 02 5D
                02 5D 00 01 00 00 02 63
                02 63 00 01 00 00 02 64
                02 64 00 01 00 00 02 65
                02 65 00 01 00 00 02 66
                02 66 00 01 00 00 02 67
                02 67 00 01 00 00 02 68
                02 68 00 01 00 00 02 69
                00 00 02 6D 00 00 02 6E
                02 6E 00 01 00 00 02 6F
                02 6F 00 01 00 00 02 70
                02 70 00 01 00 00 02 71
                02 71 00 01 00 00 02 72
                02 72 00 01 00 00 02 73
                02 73 00 01 00 00 02 74
                02 74 00 01 00 00 02 75
                02 75 00 01 00 00 02 76
                02 76 00 01 00 00 02 77
                02 77 00 01 00 00 02 78
                02 78 00 01 00 00 02 79
                00 00 02 7A 00 00 02 7B
                00 00 02 7C 02 7C 00 01
                00 00 02 7D 02 7D 00 01
                00 00 02 7E 02 7E 00 01
                00 00 02 7F 02 7F 00 01
                00 00 02 80 02 80 00 01
                00 00 02 81 00 00 02 82
                00 00 02 83 00 00 02 84
                00 00 02 85 00 00 02 86
                02 86 00 01 00 00 02 87
                00 00 02 88 00 00 02 89
                00 00 02 8A 00 00 02 8B
                00 00 02 8C 02 8C 00 01
                00 00 02 8D 00 00 02 8F
                00 00 02 90 00 00 02 91
                00 00 02 92 00 00 02 93
                00 00 02 94 00 00 02 95
                00 00 02 96 00 00 02 97
                02 97 00 01 00 00 02 98
                00 00 02 99 00 00 00 03
                00 02 00 0A 00 00 00 04
                00 02 00 0A 00 00 00 05
                00 01 00 01 00 00 00 06
                00 02 00 0A 00 00 00 07
                00 02 00 0A 00 00 00 09
                00 01 00 01 00 00 00 0D
                00 00 00 0E 00 00 00 0F
                00 00 00 10 00 00 00 11
                00 00 00 12 00 00 00 13
                00 00 00 14 00 00 00 15
                00 00 00 16 00 00 00 27
                00 00 00 3A 00 00 00 44
                00 02 00 0A 00 00 00 45
                00 00 00 46 00 00 00 4A
                00 00 00 4C 00 00 00 5B
                00 02 00 0A 00 00 00 5E
                00 01 00 01 00 00 00 5F
                00 17 00 01 00 00 00 60
                00 60 00 01 00 00 00 61
                00 60 00 01 00 00 00 64
                00 64 00 01 00 00 00 65
                00 65 00 01 00 00 00 66
                00 66 00 01 00 00 00 68
                00 00 00 69 00 00 00 6A
                00 6A 00 01 00 00 00 6C
                00 6D 00 01 00 00 00 6D
                00 6D 00 01 00 00 00 6E
                00 6F 00 01 00 00 00 6F
                00 6F 00 01 00 00 00 70
                00 70 00 01 00 00 00 71
                00 71 00 01 00 00 00 72
                00 72 00 01 00 00 00 73
                00 00 00 74 00 66 00 01
                00 00 00 76 00 00 00 77
                00 77 00 01 00 00 00 79
                00 00 00 7A 00 00 00 7B
                00 00 00 7F 00 7F 00 01
                00 00 00 88 00 00 00 92
                00 92 00 01 00 00 00 93
                00 00 00 98 00 02 00 0A
                00 00 00 99 00 02 00 0A
                00 00 00 9A 00 02 00 0A
                00 00 00 9B 00 01 00 01
                00 00 00 9C 00 0C 00 0A
                00 00 00 AC 00 02 00 0A
                00 00 00 B2 00 B2 00 01
                00 00 00 B3 00 B3 00 01
                00 00 00 B4 00 B4 00 01
                00 00 00 B5 00 B5 00 01
                00 00 00 B6 00 B6 00 01
                00 00 00 B7 00 B7 00 01
                00 00 00 B8 00 0C 00 0A
                00 00 00 B9 00 00 00 BA
                00 00 00 BB 00 00 00 BC
                00 00 00 BD 00 00 00 BE
                00 00 00 BF 00 00 00 C0
                00 00 00 C3 00 70 00 01
                00 00 00 C4 00 71 00 01
                00 00 00 C5 00 72 00 01
                00 00 00 C6 00 00 00 C7
                00 00 00 D0 00 D0 00 01
                00 00 00 D1 00 00 00 E7
                00 E7 00 01 00 00 00 E8
                00 E7 00 01 00 00 00 E9
                00 E9 00 01 00 00 00 F1
                00 6D 00 01 00 00 00 F5
                00 00 00 F6 00 00 00 FA
                00 00 00 FB 00 00 00 FC
                00 FC 00 01 00 00 02 03
                00 00 00 00 08 01 06 01
                0C 0C 41 55 54 48 5F 53
                45 53 53 4B 45 59 01 40
                40 32 43 42 37 36 41 41
                31 32 31 35 34 35 32 36
                45 33 37 44 33 34 39 31
                30 41 32 37 36 35 45 36
                34 46 32 33 36 45 39 39
                31 42 41 43 32 44 30 31
                39 32 31 32 31 44 34 39
                36 41 38 38 32 31 41 38
                34 00 01 0D 0D 41 55 54
                48 5F 56 46 52 5F 44 41
                54 41 01 20 20 36 30 33
                44 41 46 45 31 42 36 43
                45 43 39 46 34 34 44 39
                46 33 43 46 30 31 42 39
                31 43 37 45 38 02 48 15
                01 14 14 41 55 54 48 5F
                50 42 4B 44 46 32 5F 43
                53 4B 5F 53 41 4C 54 01
                20 20 32 31 32 43 30 36
                31 45 39 35 33 46 45 36
                37 32 35 32 37 45 33 44
                46 38 32 36 31 35 45 39
                31 31 00 01 16 16 41 55
                54 48 5F 50 42 4B 44 46
                32 5F 56 47 45 4E 5F 43
                4F 55 4E 54 01 04 04 34
                30 39 36 00 01 16 16 41
                55 54 48 5F 50 42 4B 44
                46 32 5F 53 44 45 52 5F
                43 4F 55 4E 54 01 01 01
                33 00 01 1A 1A 41 55 54
                48 5F 47 4C 4F 42 41 4C
                4C 59 5F 55 4E 49 51 55
                45 5F 44 42 49 44 00 01
                20 20 42 43 34 46 41 46
                42 39 32 32 38 46 41 39
                44 42 33 45 43 30 37 42
                31 46 36 36 31 36 34 44
                39 43 00 04 01 01 01 84
                00 00 00 00 00 00 00 00
                00 00 00 00 00 00 00 00
                00 00 00 01 00 00 00 00
                00 00 00 00 00 00 1D
                """)
    }
}
