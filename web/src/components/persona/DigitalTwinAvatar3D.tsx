"use client";

import { useEffect, useRef, useState } from "react";
import * as THREE from "three";
import { GLTFLoader } from "three/examples/jsm/loaders/GLTFLoader.js";

export type PersonaDimension =
  | "brain"
  | "communication"
  | "tech"
  | "execution"
  | "project"
  | "evolution"
  | "all";

export interface SynapsePulse {
  text: string;
  dimension?: PersonaDimension;
  timestamp: number;
}

interface DigitalTwinAvatar3DProps {
  activeDimension: PersonaDimension;
  onSelectDimension: (dim: PersonaDimension) => void;
  activeSynapse?: SynapsePulse | null;
  evolutionLevel?: number;
  evolutionExp?: number;
  evolutionStage?: string;
  onSparkEvolution?: () => void;
  ruleStats?: {
    ironLaws: number;
    communication: number;
    tech: number;
    execution: number;
    project: number;
  };
  className?: string;
}

const DIM_COLORS: Record<PersonaDimension, number> = {
  brain: 0xef4444, // 猩红·绝对铁律
  communication: 0x06b6d4, // 青蓝·沟通风格
  tech: 0xf59e0b, // 琥珀金·架构偏好
  execution: 0x10b981, // 翡翠绿·工作习惯
  project: 0x8b5cf6, // 维度紫·项目专属
  evolution: 0xfacc15, // 耀世金·每日进化
  all: 0xa855f7, // 全息紫·全景中枢
};

export default function DigitalTwinAvatar3D({
  activeDimension,
  onSelectDimension,
  activeSynapse,
  evolutionLevel = 9,
  evolutionExp = 860,
  evolutionStage = "认知共生体",
  onSparkEvolution,
  ruleStats = { ironLaws: 11, communication: 6, tech: 15, execution: 13, project: 5 },
  className = "",
}: DigitalTwinAvatar3DProps) {
  const containerRef = useRef<HTMLDivElement>(null);
  const [isRotating, setIsRotating] = useState(false);
  const [isRealLoaded, setIsRealLoaded] = useState(false);
  const [hudSynapse, setHudSynapse] = useState<SynapsePulse | null>(null);

  // References for live 3D mutations without React re-renders
  const avatarGroupRef = useRef<THREE.Group | null>(null);
  const solidMannequinRef = useRef<THREE.Group | null>(null);
  const bonesRef = useRef<Record<string, THREE.Object3D>>({});
  const auraRingsRef = useRef<THREE.Group | null>(null);
  const haloRef = useRef<THREE.Mesh | null>(null);
  const chestCoreRef = useRef<THREE.Mesh | null>(null);
  const ring1Ref = useRef<THREE.Mesh | null>(null);
  const ring2Ref = useRef<THREE.Mesh | null>(null);
  const spotlightRef = useRef<THREE.SpotLight | null>(null);

  // Dynamic animation states in frame loop
  const activeDimRef = useRef<PersonaDimension>(activeDimension);
  const pulseIntensityRef = useRef<number>(1.0);
  const nodProgressRef = useRef<number>(0);
  const lastSynapseTimeRef = useRef<number>(0);

  useEffect(() => {
    activeDimRef.current = activeDimension;
  }, [activeDimension]);

  // Handle Synapse Pulse from Props
  useEffect(() => {
    if (activeSynapse && activeSynapse.timestamp !== lastSynapseTimeRef.current) {
      lastSynapseTimeRef.current = activeSynapse.timestamp;
      pulseIntensityRef.current = 2.4;
      nodProgressRef.current = 1.0;
      setHudSynapse(activeSynapse);
      const timer = setTimeout(() => {
        setHudSynapse((curr) => (curr?.timestamp === activeSynapse.timestamp ? null : curr));
      }, 3500);
      return () => clearTimeout(timer);
    }
  }, [activeSynapse]);

  useEffect(() => {
    const container = containerRef.current;
    if (!container) return;

    const width = container.clientWidth || 600;
    const height = container.clientHeight || 500;

    // 1. Scene & Precision Camera Setup (Head & Torso Golden-Ratio Centered)
    const scene = new THREE.Scene();
    const camera = new THREE.PerspectiveCamera(36, width / height, 0.1, 100);
    camera.position.set(0, 1.32, 2.15);
    camera.lookAt(0, 1.22, 0);

    // 2. High-Performance WebGL Renderer
    const renderer = new THREE.WebGLRenderer({
      antialias: true,
      alpha: true,
      powerPreference: "high-performance",
    });
    renderer.setSize(width, height);
    renderer.setPixelRatio(Math.min(window.devicePixelRatio, 1.5));
    renderer.toneMapping = THREE.ACESFilmicToneMapping;
    renderer.toneMappingExposure = 1.38;
    container.appendChild(renderer.domElement);

    // 3. Studio Portrait Lighting
    const ambientLight = new THREE.AmbientLight(0xffffff, 1.6);
    scene.add(ambientLight);

    const frontKey = new THREE.DirectionalLight(0xfff7ee, 2.5);
    frontKey.position.set(0.4, 2.2, 2.8);
    scene.add(frontKey);

    const fillLight = new THREE.DirectionalLight(0xdbeafe, 1.4);
    fillLight.position.set(-1.6, 1.6, 1.8);
    scene.add(fillLight);

    const rimLight = new THREE.PointLight(0xa855f7, 3.2, 8);
    rimLight.position.set(-2.0, 2.0, -1.0);
    scene.add(rimLight);

    const spotlight = new THREE.SpotLight(0x06b6d4, 3.0, 10, Math.PI / 4, 0.4);
    spotlight.position.set(0, 3.2, 1.5);
    spotlight.target.position.set(0, 1.2, 0);
    scene.add(spotlight);
    scene.add(spotlight.target);
    spotlightRef.current = spotlight;

    // 4. Character Root Group
    const avatarGroup = new THREE.Group();
    avatarGroup.position.set(0, 0, 0);
    avatarGroupRef.current = avatarGroup;
    scene.add(avatarGroup);

    // Stand Pedestal (Sci-Fi Holographic Stage Base)
    const pedestal = new THREE.Mesh(
      new THREE.CylinderGeometry(0.75, 0.85, 0.04, 48),
      new THREE.MeshStandardMaterial({
        color: 0x141524,
        metalness: 0.85,
        roughness: 0.2,
      })
    );
    pedestal.position.set(0, 0.02, 0);
    avatarGroup.add(pedestal);

    const pedestalRing = new THREE.Mesh(
      new THREE.RingGeometry(0.7, 0.74, 48),
      new THREE.MeshBasicMaterial({ color: 0x8b5cf6, side: THREE.DoubleSide })
    );
    pedestalRing.rotation.x = -Math.PI / 2;
    pedestalRing.position.set(0, 0.042, 0);
    avatarGroup.add(pedestalRing);

    // ── Zero-Second Solid Sculpted Humanoid Figure ──
    const solidMannequin = new THREE.Group();
    solidMannequinRef.current = solidMannequin;
    avatarGroup.add(solidMannequin);

    const solidHumanMat = new THREE.MeshStandardMaterial({
      color: 0x6366f1,
      metalness: 0.7,
      roughness: 0.25,
      emissive: 0x312e81,
      emissiveIntensity: 0.2,
    });

    const jointMat = new THREE.MeshStandardMaterial({
      color: 0x8b5cf6,
      metalness: 0.85,
      roughness: 0.2,
    });

    // Head
    const solidHead = new THREE.Mesh(new THREE.SphereGeometry(0.18, 32, 24), solidHumanMat);
    solidHead.scale.set(0.9, 1.15, 0.95);
    solidHead.position.set(0, 1.62, 0);
    solidMannequin.add(solidHead);

    // Neck
    const solidNeck = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.1, 0.16, 16), solidHumanMat);
    solidNeck.position.set(0, 1.42, 0);
    solidMannequin.add(solidNeck);

    // Chest & Torso
    const solidChest = new THREE.Mesh(new THREE.CylinderGeometry(0.28, 0.22, 0.42, 20), solidHumanMat);
    solidChest.position.set(0, 1.2, 0);
    solidMannequin.add(solidChest);

    // Spine & Abdomen
    const solidSpine = new THREE.Mesh(new THREE.CylinderGeometry(0.18, 0.22, 0.32, 16), solidHumanMat);
    solidSpine.position.set(0, 0.95, 0);
    solidMannequin.add(solidSpine);

    // Shoulders
    const shoulderL = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 16), jointMat);
    shoulderL.position.set(-0.35, 1.35, 0);
    const shoulderR = new THREE.Mesh(new THREE.SphereGeometry(0.09, 16, 16), jointMat);
    shoulderR.position.set(0.35, 1.35, 0);
    solidMannequin.add(shoulderL, shoulderR);

    // Arms (Gracefully resting downward at sides)
    const armL = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.05, 0.55, 12), solidHumanMat);
    armL.position.set(-0.41, 1.05, 0.02);
    armL.rotation.z = 0.18;
    const armR = new THREE.Mesh(new THREE.CylinderGeometry(0.06, 0.05, 0.55, 12), solidHumanMat);
    armR.position.set(0.41, 1.05, 0.02);
    armR.rotation.z = -0.18;
    solidMannequin.add(armL, armR);

    // Forearms
    const foreArmL = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.04, 0.48, 12), solidHumanMat);
    foreArmL.position.set(-0.46, 0.62, 0.05);
    foreArmL.rotation.z = 0.12;
    const foreArmR = new THREE.Mesh(new THREE.CylinderGeometry(0.05, 0.04, 0.48, 12), solidHumanMat);
    foreArmR.position.set(0.46, 0.62, 0.05);
    foreArmR.rotation.z = -0.12;
    solidMannequin.add(foreArmL, foreArmR);

    // Pelvis & Legs
    const solidPelvis = new THREE.Mesh(new THREE.CylinderGeometry(0.22, 0.18, 0.22, 16), solidHumanMat);
    solidPelvis.position.set(0, 0.75, 0);
    solidMannequin.add(solidPelvis);

    const legL = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.05, 0.72, 12), solidHumanMat);
    legL.position.set(-0.12, 0.38, 0);
    const legR = new THREE.Mesh(new THREE.CylinderGeometry(0.08, 0.05, 0.72, 12), solidHumanMat);
    legR.position.set(0.12, 0.38, 0);
    solidMannequin.add(legL, legR);

    // Subtle Wisdom Halo (Resting ~8cm above hair)
    const haloMat = new THREE.MeshBasicMaterial({ color: 0xef4444, transparent: true, opacity: 0.88 });
    const haloMesh = new THREE.Mesh(new THREE.TorusGeometry(0.14, 0.005, 16, 48), haloMat);
    haloMesh.rotation.x = Math.PI / 2.2;
    haloMesh.position.set(0, 1.84, 0);
    avatarGroup.add(haloMesh);
    haloRef.current = haloMesh;

    // Tech Fusion Core inside chest
    const chestMat = new THREE.MeshBasicMaterial({ color: 0xf59e0b, transparent: true, opacity: 0.9 });
    const chestCore = new THREE.Mesh(new THREE.OctahedronGeometry(0.035, 1), chestMat);
    chestCore.position.set(0, 1.25, 0.14);
    avatarGroup.add(chestCore);
    chestCoreRef.current = chestCore;

    // Surrounding AI Terminal Orbiting Rings
    const auraGroup = new THREE.Group();
    auraGroup.position.set(0, 1.15, 0);
    avatarGroup.add(auraGroup);
    auraRingsRef.current = auraGroup;

    const ring1Mat = new THREE.MeshBasicMaterial({ color: 0x8b5cf6, transparent: true, opacity: 0.4 });
    const ring1 = new THREE.Mesh(new THREE.TorusGeometry(1.05, 0.005, 16, 80), ring1Mat);
    ring1.rotation.x = Math.PI / 2.4;
    auraGroup.add(ring1);
    ring1Ref.current = ring1;

    const ring2Mat = new THREE.MeshBasicMaterial({ color: 0x06b6d4, transparent: true, opacity: 0.35 });
    const ring2 = new THREE.Mesh(new THREE.TorusGeometry(1.35, 0.004, 16, 100), ring2Mat);
    ring2.rotation.x = Math.PI / 2.1;
    auraGroup.add(ring2);
    ring2Ref.current = ring2;

    // 5 Orbiting AI Satellites (Claude, Antigravity, Codex, OpenClaw, Hermes)
    const toolColors = [0xa855f7, 0x3b82f6, 0x10b981, 0xf59e0b, 0xec4899];
    const satellites: THREE.Mesh[] = [];
    for (let i = 0; i < 5; i++) {
      const sat = new THREE.Mesh(
        new THREE.SphereGeometry(0.035, 16, 16),
        new THREE.MeshBasicMaterial({ color: toolColors[i] })
      );
      auraGroup.add(sat);
      satellites.push(sat);
    }

    // 5. Load Real-Human Avatar
    const loader = new GLTFLoader();
    loader.load(
      "/models/avatar.glb",
      (gltf) => {
        const model = gltf.scene;
        model.scale.set(1.0, 1.0, 1.0);
        avatarGroup.add(model);
        setIsRealLoaded(true);

        solidMannequin.visible = false;

        const bones: Record<string, THREE.Object3D> = {};
        model.traverse((child) => {
          if (child instanceof THREE.Bone) {
            bones[child.name] = child;
          }
          if (child instanceof THREE.Mesh && child.material) {
            child.material.side = THREE.FrontSide;
            if ("roughness" in child.material) {
              child.material.roughness = Math.max(0.3, child.material.roughness * 0.9);
            }
          }
        });
        bonesRef.current = bones;

        // Elegant standing posture
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

        // Parent halo to Head bone
        if (bones.Head) {
          bones.Head.add(haloMesh);
          haloMesh.position.set(0, 0.16, 0);
        }
        if (bones.Spine2) {
          bones.Spine2.add(chestCore);
          chestCore.position.set(0, 0.08, 0.12);
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

    // 7. 60fps Animation Loop with Real-time Dimension Resonance
    let animId: number;
    const clock = new THREE.Clock();
    const currentColor = new THREE.Color(0xef4444);
    const targetColor = new THREE.Color(0xef4444);

    const animate = () => {
      animId = requestAnimationFrame(animate);
      const elapsed = clock.getElapsedTime();

      // Natural breathing expansion
      const breath = Math.sin(elapsed * 2.2);

      // Synapse Pulse Decay
      if (pulseIntensityRef.current > 1.0) {
        pulseIntensityRef.current = THREE.MathUtils.lerp(pulseIntensityRef.current, 1.0, 0.06);
      }

      // Nod gesture decay (affirmative response when a rule is clicked)
      let nodAngle = 0;
      if (nodProgressRef.current > 0) {
        nodAngle = Math.sin(nodProgressRef.current * Math.PI) * 0.12;
        nodProgressRef.current = Math.max(0, nodProgressRef.current - 0.04);
      }

      // Dynamic Color Interpolation based on Active Dimension
      const activeDim = activeDimRef.current;
      targetColor.setHex(DIM_COLORS[activeDim] ?? 0xa855f7);
      currentColor.lerp(targetColor, 0.08);

      // Apply dynamic colors to halo, core, and spotlight
      if (haloMat) haloMat.color.copy(currentColor);
      if (chestMat) chestMat.color.copy(currentColor);
      if (spotlightRef.current) spotlightRef.current.color.copy(currentColor);

      // 1. Mannequin breathing & nod
      if (solidMannequin.visible) {
        solidChest.scale.set(1 + breath * 0.025, 1 + breath * 0.015, 1 + breath * 0.03);
        solidHead.rotation.y = THREE.MathUtils.lerp(solidHead.rotation.y, mouse.x * 0.28, 0.06);
        solidHead.rotation.x = THREE.MathUtils.lerp(
          solidHead.rotation.x,
          -mouse.y * 0.18 + nodAngle,
          0.06
        );
      }

      // 2. Real GLB bone breathing & nod
      const bones = bonesRef.current;
      if (bones.Spine) bones.Spine.rotation.x = breath * 0.02;
      if (bones.Spine1) bones.Spine1.rotation.x = breath * 0.015;
      if (bones.Spine2) bones.Spine2.rotation.x = breath * 0.02;

      if (bones.LeftArm) bones.LeftArm.rotation.z = -1.18 + breath * 0.02;
      if (bones.RightArm) bones.RightArm.rotation.z = 1.18 - breath * 0.02;

      if (bones.Head && !isDragging) {
        bones.Head.rotation.y = THREE.MathUtils.lerp(bones.Head.rotation.y, mouse.x * 0.32, 0.06);
        bones.Head.rotation.x = THREE.MathUtils.lerp(
          bones.Head.rotation.x,
          -mouse.y * 0.2 + nodAngle,
          0.06
        );
      }

      // Auto rotation if user enables it
      if (isRotating) {
        avatarGroup.rotation.y += 0.005;
      }

      // Orbit satellites around rings (orbit speed increases during pulse)
      const orbitSpeed = (0.65 + (pulseIntensityRef.current - 1.0) * 0.8) * elapsed;
      satellites.forEach((sat, idx) => {
        const angle = orbitSpeed + (idx * Math.PI * 2) / 5;
        sat.position.set(Math.cos(angle) * 1.35, Math.sin(angle * 2) * 0.08, Math.sin(angle) * 1.35);
      });

      // Halo breathing, spinning & pulse scale
      haloMesh.rotation.z = elapsed * 0.4;
      const haloBaseScale = 1 + Math.sin(elapsed * 2.5) * 0.05;
      haloMesh.scale.setScalar(haloBaseScale * pulseIntensityRef.current);

      // Core rotation & pulse scale
      chestCore.rotation.x = elapsed * 1.2;
      chestCore.rotation.y = elapsed * 1.6;
      chestCore.scale.setScalar(pulseIntensityRef.current);

      // Always maintain camera lookAt
      camera.lookAt(0, 1.22, 0);

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
      camera.lookAt(0, 1.22, 0);
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
      className={`relative w-full h-full min-h-[460px] rounded-3xl overflow-hidden select-none border border-[var(--aurora-border)] bg-[radial-gradient(ellipse_at_50%_0%,#181a36_0%,#080912_55%,#030308_100%)] shadow-2xl flex flex-col justify-between ${className}`}
    >
      {/* 3D WebGL Canvas */}
      <div ref={containerRef} className="absolute inset-0 cursor-grab active:cursor-grabbing z-0" />

      {/* Top Floating Holographic Growth & Level HUD */}
      <div className="relative z-10 p-3.5 flex items-center justify-between pointer-events-none gap-2">
        {/* Level & Evolution Status Pill */}
        <div className="flex items-center gap-2.5 bg-black/65 backdrop-blur-xl px-3.5 py-1.5 rounded-full border border-white/15 shadow-xl pointer-events-auto">
          <div className="w-2 h-2 rounded-full bg-[#10B981] animate-ping" />
          <div className="flex items-center gap-2 text-xs">
            <span className="font-bold text-transparent bg-clip-text bg-gradient-to-r from-[#F59E0B] via-[#EC4899] to-[#8B5CF6] font-mono tracking-wide">
              Lv.{evolutionLevel} · {evolutionStage}
            </span>
            <span className="text-[10px] text-white/50 font-mono hidden sm:inline">
              EXP {evolutionExp}/1000
            </span>
          </div>
        </div>

        {/* Action Controls: Spark Evolution & Rotation */}
        <div className="flex items-center gap-1.5 pointer-events-auto">
          {onSparkEvolution && (
            <button
              onClick={() => {
                pulseIntensityRef.current = 2.8;
                nodProgressRef.current = 1.0;
                onSparkEvolution();
              }}
              title="激发今日心智进化共鸣"
              className="px-2.5 py-1 rounded-xl text-[11px] font-mono font-medium transition-all backdrop-blur-md border bg-gradient-to-r from-[#F59E0B]/20 to-[#EC4899]/20 hover:from-[#F59E0B]/35 hover:to-[#EC4899]/35 text-[#F59E0B] border-[#F59E0B]/40 hover:scale-102 flex items-center gap-1 shadow-md"
            >
              <span>⚡</span>
              <span className="hidden sm:inline">共鸣激发</span>
            </button>
          )}

          <button
            onClick={() => setIsRotating((v) => !v)}
            className={`px-2.5 py-1 rounded-xl text-[11px] font-mono font-medium transition-all backdrop-blur-md border ${
              isRotating
                ? "bg-[#A855F7]/30 text-[#C084FC] border-[#A855F7]/50"
                : "bg-black/50 text-white/70 border-white/10 hover:bg-black/70 hover:text-white"
            }`}
          >
            {isRotating ? "自转中" : "自转"}
          </button>
        </div>
      </div>

      {/* Center Dynamic Holographic Synapse Activation Banner */}
      {hudSynapse && (
        <div className="relative z-20 self-center pointer-events-none px-4 animate-in fade-in zoom-in-95 duration-200">
          <div className="bg-black/85 backdrop-blur-xl px-4 py-2.5 rounded-2xl border border-[var(--aurora-accent)] shadow-[0_0_30px_rgba(139,92,246,0.5)] flex items-center gap-2.5 max-w-[420px]">
            <span className="w-2.5 h-2.5 rounded-full bg-[var(--aurora-accent)] animate-ping shrink-0" />
            <div className="flex flex-col min-w-0">
              <span className="text-[10px] font-mono text-[var(--aurora-accent)] font-bold tracking-wider flex items-center gap-1.5">
                <span>⚡ 神经突触实时共鸣</span>
                <span className="text-white/40 font-normal">· 已沉淀至长时记忆</span>
              </span>
              <span className="text-xs text-white/95 truncate font-medium mt-0.5">
                {hudSynapse.text}
              </span>
            </div>
          </div>
        </div>
      )}

      {/* Bottom Holographic Dimension Floating Dock */}
      <div className="relative z-10 pb-3 px-3 flex justify-center pointer-events-auto">
        <div className="bg-black/65 backdrop-blur-xl border border-white/10 rounded-2xl p-1 shadow-2xl flex items-center gap-1 overflow-x-auto scrollbar-none max-w-full">
          <button
            onClick={() => onSelectDimension("all")}
            className={`px-3 py-1.2 rounded-xl text-xs font-medium transition-all shrink-0 border ${
              activeDimension === "all"
                ? "bg-[#8B5CF6] text-white border-[#8B5CF6] shadow-md font-semibold"
                : "border-transparent text-white/70 hover:text-white hover:bg-white/10"
            }`}
          >
            🌐 全景
          </button>

          {DIMENSIONS_CONFIG.map((dim) => {
            const isSelected = activeDimension === dim.id;
            return (
              <button
                key={dim.id}
                onClick={() => onSelectDimension(dim.id)}
                className={`px-2.5 py-1.2 rounded-xl text-xs font-medium transition-all shrink-0 border flex items-center gap-1.5 ${
                  isSelected
                    ? "text-white shadow-md font-semibold scale-102"
                    : "border-transparent text-white/70 hover:text-white hover:bg-white/10"
                }`}
                style={{
                  backgroundColor: isSelected ? dim.color : undefined,
                  borderColor: isSelected ? dim.color : undefined,
                }}
              >
                <span>{dim.label.split(" · ")[0]}</span>
                <span className="text-[10px] px-1.5 py-0.2 rounded-full bg-black/35 font-mono font-bold">
                  {dim.count}
                </span>
              </button>
            );
          })}
        </div>
      </div>
    </div>
  );
}
