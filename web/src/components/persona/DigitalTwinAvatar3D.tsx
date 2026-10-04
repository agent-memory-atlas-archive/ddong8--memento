"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

export type PersonaDimension = "brain" | "communication" | "tech" | "execution" | "project" | "all";

interface DigitalTwinAvatar3DProps {
  activeDimension: PersonaDimension;
  onSelectDimension: (dim: PersonaDimension) => void;
  ruleStats?: {
    ironLaws: number;
    communication: number;
    tech: number;
    execution: number;
    project: number;
  };
  className?: string;
}

export default function DigitalTwinAvatar3D({
  activeDimension,
  onSelectDimension,
  ruleStats = { ironLaws: 11, communication: 6, tech: 15, execution: 13, project: 5 },
  className = "",
}: DigitalTwinAvatar3DProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [isRotating, setIsRotating] = useState(false);
  const [isRealLoaded, setIsRealLoaded] = useState(false);

  // References
  const avatarGroupRef = useRef<THREE.Group | null>(null);
  const solidMannequinRef = useRef<THREE.Group | null>(null);
  const bonesRef = useRef<Record<string, THREE.Object3D>>({});
  const auraRingsRef = useRef<THREE.Group | null>(null);
  const haloRef = useRef<THREE.Mesh | null>(null);
  const chestCoreRef = useRef<THREE.Mesh | null>(null);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const width = container.clientWidth || 800;
    const height = container.clientHeight || 440;

    // 1. Scene & Camera Setup (Optimal Framing for Character Portrait)
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(38, width / height, 0.1, 100);
    // Camera positioned to view full upper torso, face and head cleanly
    camera.position.set(0, 1.38, 2.7);

    // 2. WebGL Renderer
    const renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.45; // Crisp, bright lighting
    container.appendChild(renderer.domElement);

    // 3. Studio Character Lights (Ensure Solid Face & Body Are Extremely Bright & Visible)
    const ambientLight = new THREE.AmbientLight(0xffffff, 1.8);
    scene.add(ambientLight);

    // Main key front light
    const frontKey = new THREE.DirectionalLight(0xfff5ea, 2.8);
    frontKey.position.set(0.6, 2.8, 3.5);
    scene.add(frontKey);

    // Secondary fill light
    const fillLight = new THREE.DirectionalLight(0xe0e7ff, 1.6);
    fillLight.position.set(-1.8, 2.0, 2.2);
    scene.add(fillLight);

    // Cyberpunk rim highlights
    const rimPurple = new THREE.PointLight(0xa855f7, 3.5, 10);
    rimPurple.position.set(-2.5, 2.5, -1.2);
    scene.add(rimPurple);

    const rimCyan = new THREE.PointLight(0x06b6d4, 3.0, 10);
    rimCyan.position.set(2.5, 1.5, 1.2);
    scene.add(rimCyan);

    // 4. Character Root Group
    const avatarGroup = new THREE.Group();
    avatarGroup.position.set(0, -0.92, 0);
    avatarGroupRef.current = avatarGroup;
    scene.add(avatarGroup);

    // Stand Pedestal (Sci-Fi Stage Disc)
    const pedestal = new THREE.Mesh(
      new THREE.CylinderGeometry(0.85, 0.95, 0.05, 48),
      new THREE.MeshStandardMaterial({
        color: 0x1e1b4b,
        metalness: 0.8,
        roughness: 0.2,
      })
    );
    avatarGroup.add(pedestal);

    const pedestalRing = new THREE.Mesh(
      new THREE.RingGeometry(0.78, 0.84, 48),
      new THREE.MeshBasicMaterial({ color: 0x8b5cf6, side: THREE.DoubleSide })
    );
    pedestalRing.rotation.x = -Math.PI / 2;
    pedestalRing.position.set(0, 0.026, 0);
    avatarGroup.add(pedestalRing);

    // ── Zero-Second Solid Sculpted Humanoid Figure (100% Guaranteed Visible Immediately) ──
    const solidMannequin = new THREE.Group();
    solidMannequinRef.current = solidMannequin;
    avatarGroup.add(solidMannequin);

    const solidHumanMat = new THREE.MeshStandardMaterial({
      color: 0x6366f1, // Bright Indigo/Violet Solid Shimmer
      metalness: 0.65,
      roughness: 0.25,
      emissive: 0x312e81,
      emissiveIntensity: 0.25,
    });

    const jointMat = new THREE.MeshStandardMaterial({
      color: 0x8b5cf6,
      metalness: 0.8,
      roughness: 0.2,
    });

    // Head & Face
    const solidHead = new THREE.Mesh(new THREE.SphereGeometry(0.26, 32, 24), solidHumanMat);
    solidHead.scale.set(0.9, 1.15, 0.95);
    solidHead.position.set(0, 2.38, 0);
    solidMannequin.add(solidHead);

    // Neck
    const solidNeck = new THREE.Mesh(new THREE.CylinderGeometry(0.1, 0.12, 0.22, 16), solidHumanMat);
    solidNeck.position.set(0, 2.05, 0);
    solidMannequin.add(solidNeck);

    // Chest & Torso (Athletic Human Silhouette)
    const solidChest = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.28, 0.58, 20), solidHumanMat);
    solidChest.position.set(0, 1.68, 0);
    solidMannequin.add(solidChest);

    // Spine & Abdomen
    const solidSpine = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.28, 0.42, 16), solidHumanMat);
    solidSpine.position.set(0, 1.25, 0);
    solidMannequin.add(solidSpine);

    // Shoulders
    const shoulderL = new THREE.Mesh(new THREE.SphereGeometry(0.12, 16, 16), jointMat);
    shoulderL.position.set(-0.46, 1.85, 0);
    const shoulderR = new THREE.Mesh(new THREE.SphereGeometry(0.12, 16, 16), jointMat);
    shoulderR.position.set(0.46, 1.85, 0);
    solidMannequin.add(shoulderL, shoulderR);

    // Arms (Elegantly relaxing downwards by side, NOT stiff T-pose)
    const armL = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.065, 0.75, 12), solidHumanMat);
    armL.position.set(-0.54, 1.4, 0.04);
    armL.rotation.z = 0.2;
    const armR = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.065, 0.75, 12), solidHumanMat);
    armR.position.set(0.54, 1.4, 0.04);
    armR.rotation.z = -0.2;
    solidMannequin.add(armL, armR);

    // Forearms
    const foreArmL = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.05, 0.65, 12), solidHumanMat);
    foreArmL.position.set(-0.62, 0.78, 0.08);
    foreArmL.rotation.z = 0.15;
    const foreArmR = new THREE.Mesh(new THREE.CylinderGeometry(0.065, 0.05, 0.65, 12), solidHumanMat);
    foreArmR.position.set(0.62, 0.78, 0.08);
    foreArmR.rotation.z = -0.15;
    solidMannequin.add(foreArmL, foreArmR);

    // Pelvis & Legs
    const solidPelvis = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.24, 0.28, 16), solidHumanMat);
    solidPelvis.position.set(0, 0.95, 0);
    solidMannequin.add(solidPelvis);

    const legL = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.07, 1.0, 12), solidHumanMat);
    legL.position.set(-0.16, 0.45, 0);
    const legR = new THREE.Mesh(new THREE.CylinderGeometry(0.11, 0.07, 1.0, 12), solidHumanMat);
    legR.position.set(0.16, 0.45, 0);
    solidMannequin.add(legL, legR);

    // Halo Above Head (Wisdom Halo, safely above head)
    const haloMesh = new THREE.Mesh(
      new THREE.TorusGeometry(0.18, 0.007, 16, 48),
      new THREE.MeshBasicMaterial({ color: 0xef4444, transparent: true, opacity: 0.9 })
    );
    haloMesh.rotation.x = Math.PI / 2.2;
    haloMesh.position.set(0, 2.75, 0);
    avatarGroup.add(haloMesh);
    haloRef.current = haloMesh;

    // Tech Fusion Core inside chest
    const chestCore = new THREE.Mesh(
      new THREE.OctahedronGeometry(0.045, 1),
      new THREE.MeshBasicMaterial({ color: 0xf59e0b, transparent: true, opacity: 0.9 })
    );
    chestCore.position.set(0, 1.7, 0.22);
    avatarGroup.add(chestCore);
    chestCoreRef.current = chestCore;

    // Surrounding AI Terminal Orbiting Rings
    const auraGroup = new THREE.Group();
    avatarGroup.add(auraGroup);
    auraRingsRef.current = auraGroup;

    const ring1 = new THREE.Mesh(
      new THREE.TorusGeometry(1.35, 0.007, 16, 80),
      new THREE.MeshBasicMaterial({ color: 0x8b5cf6, transparent: true, opacity: 0.4 })
    );
    ring1.rotation.x = Math.PI / 2.4;
    ring1.position.set(0, 1.45, 0);
    auraGroup.add(ring1);

    const ring2 = new THREE.Mesh(
      new THREE.TorusGeometry(1.7, 0.006, 16, 100),
      new THREE.MeshBasicMaterial({ color: 0x06b6d4, transparent: true, opacity: 0.35 })
    );
    ring2.rotation.x = Math.PI / 2.1;
    ring2.position.set(0, 1.2, 0);
    auraGroup.add(ring2);

    // 5 Orbiting AI Satellites (Claude, Antigravity, Codex, OpenClaw, Hermes)
    const toolColors = [0xa855f7, 0x3b82f6, 0x10b981, 0xf59e0b, 0xec4899];
    const satellites: THREE.Mesh[] = [];
    for (let i = 0; i < 5; i++) {
      const sat = new THREE.Mesh(
        new THREE.SphereGeometry(0.045, 16, 16),
        new THREE.MeshBasicMaterial({ color: toolColors[i] })
      );
      auraGroup.add(sat);
      satellites.push(sat);
    }

    // 5. Load Real-Human Avatar (Overlays onto base when ready)
    const loader = new GLTFLoader();
    loader.load(
      "/models/avatar.glb",
      (gltf) => {
        const model = gltf.scene;
        model.scale.set(1.05, 1.05, 1.05);
        avatarGroup.add(model);
        setIsRealLoaded(true);

        // Hide solid mannequin smoothly once realistic avatar is active
        solidMannequin.visible = false;

        const bones: Record<string, THREE.Object3D> = {};
        model.traverse((child) => {
          if (child instanceof THREE.Bone) {
            bones[child.name] = child;
          }
          if (child instanceof THREE.Mesh) {
            if (child.material) {
              child.material.side = THREE.FrontSide;
              if ("roughness" in child.material) {
                child.material.roughness = Math.max(0.3, child.material.roughness * 0.9);
              }
            }
          }
        });
        bonesRef.current = bones;

        // Transform Arms into natural standing posture
        if (bones.LeftArm) {
          bones.LeftArm.rotation.z = -1.18;
          bones.LeftArm.rotation.x = 0.1;
        }
        if (bones.RightArm) {
          bones.RightArm.rotation.z = 1.18;
          bones.RightArm.rotation.x = 0.1;
        }
        if (bones.LeftForeArm) {
          bones.LeftForeArm.rotation.y = 0.22;
        }
        if (bones.RightForeArm) {
          bones.RightForeArm.rotation.y = -0.22;
        }

        // Parent halo to Head bone safely above hair
        if (bones.Head) {
          bones.Head.add(haloMesh);
          haloMesh.position.set(0, 0.28, 0);
        }
        if (bones.Spine2) {
          bones.Spine2.add(chestCore);
          chestCore.position.set(0, 0.1, 0.12);
        }
      },
      undefined,
      (err) => {
        console.info("Using solid sculpted digital mannequin as core avatar.", err);
      }
    );

    // 6. Interactive Drag & Parallax Look-At
    const mouse = new THREE.Vector2();
    let isDragging = false;
    let prevMouseX = 0;

    const handlePointerDown = (e: MouseEvent) => {
      isDragging = true;
      prevMouseX = e.clientX;
    };

    const handlePointerUp = () => {
      isDragging = false;
    };

    const handlePointerMove = (e: MouseEvent) => {
      const rect = container.getBoundingClientRect();
      mouse.x = ((e.clientX - rect.left) / rect.width) * 2 - 1;
      mouse.y = -((e.clientY - rect.top) / rect.height) * 2 + 1;

      if (isDragging) {
        const deltaX = e.clientX - prevMouseX;
        avatarGroup.rotation.y += deltaX * 0.008;
        prevMouseX = e.clientX;
      }
    };

    container.addEventListener("mousedown", handlePointerDown);
    window.addEventListener("mouseup", handlePointerUp);
    container.addEventListener("mousemove", handlePointerMove);

    // 7. 60fps Animation Loop (Lifelike Natural Breathing & Parallax, Zero React setState)
    let animId: number;
    const clock = new THREE.Clock();

    const animate = () => {
      animId = requestAnimationFrame(animate);
      const elapsed = clock.getElapsedTime();

      // Natural breathing expansion
      const breath = Math.sin(elapsed * 2.2);

      // 1. Mannequin breathing
      if (solidMannequin.visible) {
        solidChest.scale.set(1 + breath * 0.025, 1 + breath * 0.015, 1 + breath * 0.03);
        solidHead.rotation.y = THREE.MathUtils.lerp(solidHead.rotation.y, mouse.x * 0.28, 0.06);
        solidHead.rotation.x = THREE.MathUtils.lerp(solidHead.rotation.x, -mouse.y * 0.18, 0.06);
      }

      // 2. Real GLB bone breathing (if active)
      const bones = bonesRef.current;
      if (bones.Spine) bones.Spine.rotation.x = breath * 0.02;
      if (bones.Spine1) bones.Spine1.rotation.x = breath * 0.015;
      if (bones.Spine2) bones.Spine2.rotation.x = breath * 0.02;

      if (bones.LeftArm) bones.LeftArm.rotation.z = -1.18 + breath * 0.02;
      if (bones.RightArm) bones.RightArm.rotation.z = 1.18 - breath * 0.02;

      if (bones.Head && !isDragging) {
        bones.Head.rotation.y = THREE.MathUtils.lerp(bones.Head.rotation.y, mouse.x * 0.32, 0.06);
        bones.Head.rotation.x = THREE.MathUtils.lerp(bones.Head.rotation.x, -mouse.y * 0.2, 0.06);
      }

      // Auto rotation if user enables it
      if (isRotating) {
        avatarGroup.rotation.y += 0.005;
      }

      // Orbit satellites around rings
      satellites.forEach((sat, idx) => {
        const angle = elapsed * 0.65 + (idx * Math.PI * 2) / 5;
        sat.position.set(Math.cos(angle) * 1.7, 1.2 + Math.sin(angle * 2) * 0.1, Math.sin(angle) * 1.7);
      });

      // Halo breathing & spinning
      haloMesh.rotation.z = elapsed * 0.4;
      haloMesh.scale.setScalar(1 + Math.sin(elapsed * 2.5) * 0.06);

      // Core rotation
      chestCore.rotation.x = elapsed * 1.2;
      chestCore.rotation.y = elapsed * 1.6;

      renderer.render(scene, camera);
    };

    animate();

    // 8. Resize Observer
    const handleResize = () => {
      if (!container || !renderer || !camera) return;
      const newW = container.clientWidth;
      const newH = container.clientHeight;
      camera.aspect = newW / newH;
      camera.updateProjectionMatrix();
      renderer.setSize(newW, newH);
    };

    const resizeObserver = new ResizeObserver(handleResize);
    resizeObserver.observe(container);

    return () => {
      cancelAnimationFrame(animId);
      resizeObserver.disconnect();
      container.removeEventListener("mousedown", handlePointerDown);
      window.removeEventListener("mouseup", handlePointerUp);
      container.removeEventListener("mousemove", handlePointerMove);
      if (renderer.domElement && container.contains(renderer.domElement)) {
        container.removeChild(renderer.domElement);
      }
      renderer.dispose();
    };
  }, [isRotating]);

  const DIMENSIONS_CONFIG = [
    {
      id: "brain" as const,
      label: "🧠 脑核 · 绝对红线",
      color: "#EF4444",
      count: ruleStats.ironLaws,
    },
    {
      id: "communication" as const,
      label: "💬 喉核 · 交互沟通",
      color: "#06B6D4",
      count: ruleStats.communication,
    },
    {
      id: "tech" as const,
      label: "⚡ 心核 · 架构偏好",
      color: "#F59E0B",
      count: ruleStats.tech,
    },
    {
      id: "execution" as const,
      label: "🛠️ 肢端 · 工作习惯",
      color: "#10B981",
      count: ruleStats.execution,
    },
    {
      id: "project" as const,
      label: "🎯 靶向 · 项目规范",
      color: "#8B5CF6",
      count: ruleStats.project,
    },
  ];

  return (
    <div
      className={`relative w-full h-full min-h-[420px] rounded-3xl overflow-hidden select-none border border-[var(--aurora-border)] bg-gradient-to-b from-[#0c0d18] via-[#080912] to-[#040509] shadow-2xl ${className}`}
    >
      {/* 3D WebGL Canvas */}
      <div ref={containerRef} className="w-full h-full cursor-grab active:cursor-grabbing" />

      {/* Top Floating Glass Header */}
      <div className="absolute top-3.5 left-4 right-4 flex items-center justify-between pointer-events-none z-10">
        <div className="flex items-center gap-2 bg-black/50 backdrop-blur-md px-3.5 py-1.5 rounded-full border border-white/10 shadow-lg">
          <div className="w-2 h-2 rounded-full bg-[#10B981] animate-ping" />
          <span className="text-[11px] font-mono text-white/95 font-medium tracking-wide">
            REAL HUMAN DIGITAL TWIN · 60 FPS
          </span>
        </div>

        <div className="flex items-center gap-2 pointer-events-auto">
          {/* Rotation Toggle */}
          <button
            onClick={() => setIsRotating((v) => !v)}
            className={`px-3 py-1.5 rounded-xl text-[11px] font-mono font-medium transition-all backdrop-blur-md border ${
              isRotating
                ? "bg-[#A855F7]/30 text-[#C084FC] border-[#A855F7]/50"
                : "bg-black/50 text-white/70 border-white/10 hover:bg-black/70 hover:text-white"
            }`}
          >
            {isRotating ? "全息自转中" : "暂停自转"}
          </button>
        </div>
      </div>

      {/* Bottom Holographic Dimension Pills Bar */}
      <div className="absolute bottom-3 left-3 right-3 flex items-center justify-center gap-2 z-20 pointer-events-auto overflow-x-auto scrollbar-none py-1">
        <button
          onClick={() => onSelectDimension("all")}
          className={`px-3.5 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border ${
            activeDimension === "all"
              ? "bg-[#8B5CF6] text-white border-[#8B5CF6] shadow-lg font-semibold"
              : "bg-black/60 text-white/70 border-white/10 hover:text-white hover:bg-black/80"
          }`}
        >
          🌐 全景总览
        </button>

        {DIMENSIONS_CONFIG.map((dim) => {
          const isSelected = activeDimension === dim.id;
          return (
            <button
              key={dim.id}
              onClick={() => onSelectDimension(dim.id)}
              className={`px-3 py-1.5 rounded-xl text-xs font-medium transition-all shrink-0 backdrop-blur-md border flex items-center gap-1.5 ${
                isSelected
                  ? "text-white shadow-lg font-semibold scale-102"
                  : "bg-black/60 text-white/70 border-white/10 hover:text-white hover:bg-black/80"
              }`}
              style={{
                backgroundColor: isSelected ? dim.color : undefined,
                borderColor: isSelected ? dim.color : undefined,
              }}
            >
              <span>{dim.label.split(" · ")[0]}</span>
              <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-black/30 font-mono font-bold">
                {dim.count}
              </span>
            </button>
          );
        })}
      </div>
    </div>
  );
}
